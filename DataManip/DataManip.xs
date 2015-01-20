#define PERL_NO_GET_CONTEXT
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include <pthread.h>
#include <errno.h>
#include <time.h>
#include <stdlib.h>
#include <stdbool.h>

#include "ringbuffer.h"

#define READERS_THREADS_COUNT 5

#ifndef MAX_THREADS
#	define MAX_THREADS (3 + READERS_THREADS_COUNT)
#endif

#if MAX_THREADS < READERS_THREADS_COUNT
#	error "MAX_THREADS NEED TO BE LARGER"
#endif

#define SLEEP_TIME 100

#ifndef LOG_LEVEL
#	define LOG_LEVEL 0
#endif

#ifndef BLOCK_SIZE
#	define BLOCK_SIZE 4096
#endif

static int log_level = LOG_LEVEL;

#define log_msg(args...) ({			\
	if (log_level > 3)			\
		printf("[INFO] " args);		\
})

#define err_msg(args...) ({			\
	printf("[ERROR] " args);		\
})

typedef struct {
	char *ptr;
	size_t content_len;
	int block_no;
} buffer_content_t;

typedef struct {
	char data[BLOCK_SIZE];
	bool available;
} real_buffer_t;

typedef struct {
	SV *var;
	size_t block_len;
	pthread_mutex_t *mutex;
	PerlInterpreter *perl;
} reader_content_t;

ringBuffer_typedef(buffer_content_t, ring_buffer_t);

static ring_buffer_t *ring_buffer;
static real_buffer_t *data_block;

static pthread_t threads[MAX_THREADS];
static short threads_count = 0;

static pthread_mutex_t data_mutex = PTHREAD_MUTEX_INITIALIZER;
static pthread_rwlock_t ring_lock = PTHREAD_RWLOCK_INITIALIZER;

static bool need_stop;

static void stop_threads() {
	int i = 0;
	for (; i < threads_count; ++i) {
		int res = pthread_join(threads[i], NULL);
		if (res != 0)
			err_msg("Can't stop thread #%d: %s\n", i, strerror(res));
	}
	threads_count = 0;
	memset(threads, 0, sizeof(threads));
}

static int start_thread(void *(*thread_routine)(void *)) {
	if (threads_count >= sizeof(threads) / sizeof(*threads) - READERS_THREADS_COUNT) {
		err_msg("Too many threads\n");
		return -1;
	}

	int res = pthread_create(threads + threads_count, NULL, thread_routine, &threads_count);
	if (res != 0) {
		err_msg("Can't create thread #%d: %s\n", threads_count, strerror(res));
		return -1;
	}

	return threads_count++;
}

static size_t get_content(buffer_content_t *content) {
	content->content_len = 0;
	pthread_rwlock_wrlock(&ring_lock);
	if (!isBufferEmpty(ring_buffer))
		bufferRead(ring_buffer, *content);
	pthread_rwlock_unlock(&ring_lock);

	return content->content_len;
}

static bool have_data() {
	bool have_data = false;

	pthread_rwlock_rdlock(&ring_lock);
	have_data = !isBufferFull(ring_buffer);
	pthread_rwlock_unlock(&ring_lock);

	return have_data;
}

static int find_empty_block() {
	int i = 0, r = -1;

	if (have_data()) {
		pthread_mutex_lock(&data_mutex);

		for (; r < 0 && i < ring_buffer->size; i++) {
			if (data_block[i].available) {
				data_block[i].available = false;
				r = i;
			}
		}

		pthread_mutex_unlock(&data_mutex);
	}

	return r;
}

static void *data_xorer_routine(void *arg) {
	log_msg("Xorer #%d started\n", *(int *)(arg));

	buffer_content_t content, new_content;

	while (!need_stop) {
		int block_no = find_empty_block();

		if (block_no < 0) {
			usleep(SLEEP_TIME);
			continue;
		}

		while (get_content(&content) == 0 || content.content_len < sizeof(data_block[block_no].data) / 2) {
			usleep(SLEEP_TIME);
		}

		memcpy(data_block[block_no].data, content.ptr, content.content_len);

		new_content.ptr = data_block[block_no].data;
		new_content.content_len = content.content_len;
		new_content.block_no = block_no;
		int *data = (int *)new_content.ptr;

		int r = rand();
		while ((char *)data < content.ptr) {
			*data ^= r;
			++data;
		}

		pthread_rwlock_wrlock(&ring_lock);
		bufferWrite(ring_buffer, content);
		bufferWrite(ring_buffer, new_content);
		pthread_rwlock_unlock(&ring_lock);
	}

	log_msg("Xorer #%d stopped\n", *(int *)(arg));

	return NULL;
}

static void *data_writer_routine(void *arg) {
	log_msg("Writer started\n");
	const char *dev_name = "/dev/urandom";
	FILE *dev = fopen(dev_name, "r");
	if (dev == NULL)
		die("Can't open %s: %s\n", dev_name, strerror(errno));

	log_msg("%s dev opened successfully\n", dev_name);
	while (!need_stop) {
		int block_no = find_empty_block();

		if (block_no < 0) {
			usleep(SLEEP_TIME);
			continue;
		}

		buffer_content_t content;
		content.ptr = data_block[block_no].data;
		content.content_len = sizeof(data_block[block_no].data);
		content.block_no = block_no;

		size_t readed = fread(content.ptr, content.content_len, 1, dev);
		if (readed != 1) {
			err_msg("Can't read 1 block of size %lu from %s\n", content.content_len, dev_name);
			continue;
		}

		pthread_rwlock_wrlock(&ring_lock);
		bufferWrite(ring_buffer, content);
		log_msg("%lu bytes read from %s [%d blocks in queue]\n", content.content_len, dev_name, bufferLength(ring_buffer));
		pthread_rwlock_unlock(&ring_lock);
	}

	log_msg("Writer stopped\n");

	return NULL;
}

static void *data_reader_routine(void *arg) {
	reader_content_t *dst = (reader_content_t *)arg;

	int try_no = 0;

	register PerlInterpreter *my_perl __attribute__((unused)) = dst->perl;
	buffer_content_t content;
	while (dst->block_len > 0) {
		get_content(&content);

		if (content.content_len == 0) {
			log_msg("Can't get block of size %lu [%d blocks in queue] [try = %d]\n",
					dst->block_len, bufferLength(ring_buffer), ++try_no);

			if (try_no > 20) {
				start_thread(&data_xorer_routine);
				try_no = 0;
			}

			usleep(SLEEP_TIME);
			continue;
		}

		size_t len = dst->block_len;
		char *ptr = content.ptr;
		if (content.content_len >= dst->block_len) {
			content.ptr += dst->block_len;
			content.content_len -= dst->block_len;
			dst->block_len = 0;
		} else {
			len = content.content_len;
			dst->block_len -= content.content_len;
			content.content_len = 0;

			data_block[content.block_no].available = true;
		}

		pthread_mutex_lock(dst->mutex);
		sv_catpvn(dst->var, ptr, len);
		pthread_mutex_unlock(dst->mutex);

		if (content.content_len > 0) {
			pthread_rwlock_wrlock(&ring_lock);
			bufferWrite(ring_buffer, content);
			pthread_rwlock_unlock(&ring_lock);
		}
	}

	return NULL;
}

// ================================================

MODULE = DataManip		PACKAGE = DataManip

SV *
read_block(var, length)
	SV* var
	size_t length
	CODE:
		if (!SvROK(var) || SvTYPE(var) != SVt_RV)
			croak("Not a reference");

		SvREFCNT_inc(var);
		SV *data = SvRV(var);

		if (!SvPOK(data))
			croak("Not a scalar reference");
		sv_setpvn(data, "", 0);
		SvGROW(data, length + 1);

		pthread_mutex_t mutex = PTHREAD_MUTEX_INITIALIZER;
		reader_content_t readers[READERS_THREADS_COUNT];

		int i;
		const int count = sizeof(readers) / sizeof(*readers);

		for (i = 0; i < count; ++i) {
			readers[i].mutex = &mutex;
			readers[i].var = data;
			readers[i].block_len = 0;
			readers[i].perl = my_perl; // variable will be generated on preprocessing
		}

		int threads_count = 0;
		if (length >= 10 * 1024 * 1024) {
			// 10 Mb
			size_t data_size = 0;
			for (i = 0; i < count; ++i) {
				int c = (i == count - 1 ? 1 : (count - threads_count));
				readers[i].block_len = (length - data_size) / c;
				data_size += readers[i].block_len;

				int res = pthread_create(threads + sizeof(threads) / sizeof(*threads) - i - 1,
						NULL, data_reader_routine, readers + i);
				if (res != 0)
					err_msg("Can't create reader thread #%d: %s\n", i, strerror(res));
				else
					++threads_count;
			}

			for (i = 0; i < count; ++i) {
				pthread_t *th = threads + sizeof(threads) / sizeof(*threads) - i - 1;
				pthread_join(*th, NULL);
				memset(th, 0, sizeof(*th));
			}
		} else {
			readers->block_len = length;
			data_reader_routine(readers);
		}

		RETVAL = var;
	OUTPUT:
		RETVAL

void
start(blocks_count)
	int blocks_count
	CODE:
		srand(time(NULL));

		if (blocks_count < 0)
			die("Invalid blocks count given: %d", blocks_count);

		if (data_block)
			free(data_block);

		data_block = (real_buffer_t *)calloc(sizeof(real_buffer_t), blocks_count + 1);
		if (!data_block)
			die("Can't alloc %ld bytes: no mem\n", sizeof(real_buffer_t) * (blocks_count + 1));

		ring_buffer = (ring_buffer_t *)malloc(sizeof(ring_buffer_t));
		bufferInit(*ring_buffer, blocks_count, buffer_content_t);

		int i = 0;
		for (; i < blocks_count + 1; ++i)
			data_block[i].available = true;

		need_stop = false;
		start_thread(&data_writer_routine);

void
stop()
	CODE:
		log_msg("Stopping threads...\n");

		need_stop = true;
		stop_threads();

		if (ring_buffer) {
			bufferDestroy(ring_buffer);
			free(ring_buffer);
		}

		if (data_block)
			free(data_block);

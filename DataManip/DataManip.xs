#define PERL_NO_GET_CONTEXT
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include <pthread.h>
#include <errno.h>
#include <time.h>
#include <stdlib.h>

#include "ringbuffer.h"

#define MAX_THREADS 10
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
	if (threads_count >= sizeof(threads) / sizeof(*threads)) {
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
	have_data = isBufferFull(ring_buffer);
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

	return NULL;
}

static void *data_writer_routine(void *arg) {
	log_msg("Writer started\n");
	FILE *dev = fopen("/dev/urandom", "r");
	if (dev == NULL)
		die("Can't open /dev/urandom: %s\n", strerror(errno));

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

		fread(content.ptr, content.content_len, 1, dev);

		pthread_rwlock_wrlock(&ring_lock);
		bufferWrite(ring_buffer, content);
		pthread_rwlock_unlock(&ring_lock);
	}

	return NULL;
}

// ================================================

MODULE = DataManip		PACKAGE = DataManip

SV *
read_block(length)
	size_t length
	CODE:
		RETVAL = newSV(length);
		SV *ptr = RETVAL;

		int try_no = 0;

		buffer_content_t content;
		while (length > 0) {
			get_content(&content);

			if (try_no > 3) {
				start_thread(&data_xorer_routine);
			}

			if (content.content_len == 0) {
				try_no++;
				usleep(SLEEP_TIME);
				continue;
			}

			if (content.content_len >= length) {
				memcpy(ptr, content.ptr, length);
				content.ptr += length;
				content.content_len -= length;
				length = 0;
			} else {
				length -= content.content_len;
				memcpy(ptr, content.ptr, content.content_len);
				ptr += content.content_len;
				content.content_len = 0;

				data_block[content.block_no].available = true;
			}

			if (content.content_len > 0) {
				pthread_rwlock_wrlock(&ring_lock);
				bufferWrite(ring_buffer, content);
				pthread_rwlock_unlock(&ring_lock);
			}
		}

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
		need_stop = true;
		stop_threads();

		if (ring_buffer) {
			bufferDestroy(ring_buffer);
			free(ring_buffer);
		}

		if (data_block)
			free(data_block);

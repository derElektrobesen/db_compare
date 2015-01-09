#define PERL_NO_GET_CONTEXT
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include <pthread.h>
#include <errno.h>
#include <time.h>

#include "ringbuffer.h"

#define MAX_THREADS 10

#ifdef LOG_LEVEL
	static int log_level = LOG_LEVEL;
#else
	static int log_level = 0;
#endif

#ifndef BLOCK_SIZE
#	define BLOCK_SIZE 4096
#endif

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

static int find_empty_block() {
	int i = 0, r = -1;
	bool need_wait = false;

	pthread_rwlock_rdlock(&ring_lock);
	need_wait = isBufferFull(ring_buffer);
	pthread_rwlock_unlock(&ring_lock);

	if (!need_wait) {
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

static void *data_writer_routine(void *arg) {
	log_msg("Writer started");
	FILE *dev = fopen("/dev/urandom", "r");
	if (dev == NULL)
		die("Can't open /dev/urandom: %s\n", strerror(errno));

	while (!need_stop) {
		char *ptr = NULL;

		int block_no = find_empty_block();

		if (block_no < 0) {
			usleep(100);
			continue;
		}

		buffer_content_t content;
		content.ptr = data_block[block_no].data;
		content.content_len = sizeof(data_block[block_no].data);

		fread(content.ptr, content.content_len, 1, dev);

		pthread_rwlock_wrlock(&ring_lock);
		bufferWrite(ring_buffer, content);
		pthread_rwlock_unlock(&ring_lock);
	}

	return NULL;
}

// ================================================

MODULE = DataManip		PACKAGE = DataManip

void
start(blocks_count)
	int blocks_count
	CODE:
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

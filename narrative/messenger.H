/* messenger.h -- simple inbox of delivered messages. */
#ifndef MESSENGER_H
#define MESSENGER_H
#include <stdint.h>

#define MSG_CAP 256

/* on_read hooks: optional callbacks fired when a message is marked read. */
typedef void (*msg_onread_fn)(uint32_t id, uint16_t from, const char *text);

void msg_init(void);
/* adds a message from `from` to the inbox and returns its id (1-based) */
uint32_t msg_deliver(uint16_t from, const char *text);
void msg_mark_read(uint32_t id);
int  msg_count(void);   /* number of unread messages */
void msg_set_onread(msg_onread_fn fn);

#endif /* MESSENGER_H */

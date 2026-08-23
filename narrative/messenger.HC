/* messenger.c -- simple inbox of delivered messages.
 * Recreated implementation after a bad rename overwrote the original .c. */
#include <string.h>
#include <stdint.h>
#include "messenger.H"

typedef struct {
  uint32_t id;
  uint16_t from;
  char     text[256];
  int      read;
} Msg;

static Msg          g_msg[MSG_CAP];
static int          g_msg_n = 0;
static uint32_t     g_msg_next = 1;
static msg_onread_fn g_onread = NULL;

void msg_init(void){
  memset(g_msg, 0, sizeof(g_msg));
  g_msg_n = 0;
  g_msg_next = 1;
  g_onread = NULL;
}

uint32_t msg_deliver(uint16_t from, const char *text){
  if(g_msg_n >= MSG_CAP) return 0;
  Msg *m = &g_msg[g_msg_n++];
  m->id = g_msg_next++;
  m->from = from;
  m->read = 0;
  strncpy(m->text, text ? text : "", sizeof(m->text) - 1);
  m->text[sizeof(m->text) - 1] = 0;
  return m->id;
}

void msg_mark_read(uint32_t id){
  for(int i=0;i<g_msg_n;i++){
    if(g_msg[i].id == id && !g_msg[i].read){
      g_msg[i].read = 1;
      if(g_onread) g_onread(g_msg[i].id, g_msg[i].from, g_msg[i].text);
      return;
    }
  }
}

int msg_count(void){
  int unread = 0;
  for(int i=0;i<g_msg_n;i++) if(!g_msg[i].read) unread++;
  return unread;
}

void msg_set_onread(msg_onread_fn fn){ g_onread = fn; }

/* dsl.c -- scene scripting language (parser + interpreter) for 퇴근.
 * Recreated implementation: the original .c was lost in a bad rename that
 * overwrote it with the .h. Parses .ssc scene files and runs them, stopping
 * at `choice:` blocks and resuming via dsl_choice(). */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "dsl.H"
#include "relationships.H"
#include "campaign.H"
#include "messenger.H"
#include "../include/contracts.HC"

/* ---- global player state (defined here; declared extern in dsl.H) ---- */
PlayerStats  g_player;
PendingChoice g_pending_choice;
int          g_cards_added;

/* ---- scene storage ---- */
#define MAXNODE  64
#define MAXSTMT  64
#define MAXSCENE 32

typedef enum {
  ST_SAY, ST_REL, ST_STAT, ST_GOTO, ST_FLAG, ST_CARD,
  ST_MSG, ST_COMBAT, ST_SCHEDULE, ST_RETURN
} StmtType;

typedef struct {
  StmtType type;
  char speaker[64];
  char text[256];
  char npc[32];
  char field[32];
  int  delta;
  char flag[64];
  char card[64];
  char target[64];
} Stmt;

typedef struct {
  char label[64];
  int  is_choice;
  int  n_opt;
  char opt_label[CHOICE_CAP][64];
  char opt_target[CHOICE_CAP][64];
  int  opt_has_guard[CHOICE_CAP];
  int  opt_guard_stat[CHOICE_CAP];
  int  opt_guard_min[CHOICE_CAP];
  Stmt stmts[MAXSTMT];
  int  n_stmts;
} Node;

typedef struct {
  char name[64];
  Node nodes[MAXNODE];
  int  n_nodes;
} Scene;

static Scene g_scenes[MAXSCENE];
static int   g_nscenes = 0;

/* execution cursor */
static int g_cur_scene = -1;
static int g_cur_node  = -1;
static int g_cur_stmt  = 0;

/* ---- helpers ---- */
static void trim(char *s){
  if(!s) return;
  char *a = s, *b = s + strlen(s);
  while(a < b && (*a==' '||*a=='\t'||*a=='\r'||*a=='\n')) a++;
  while(b > a && (b[-1]==' '||b[-1]=='\t'||b[-1]=='\r'||b[-1]=='\n')) b--;
  memmove(s, a, (size_t)(b - a));
  s[b - a] = 0;
}

static int player_stat_index(const char *n){
  if(!strcmp(n,"hp"))      return 0;
  if(!strcmp(n,"energy"))  return 1;
  if(!strcmp(n,"focus"))   return 2;
  if(!strcmp(n,"nunchi"))  return 3;
  if(!strcmp(n,"balls"))   return 4;
  if(!strcmp(n,"perf"))    return 5;
  if(!strcmp(n,"net"))     return 6;
  if(!strcmp(n,"spec"))    return 7;
  if(!strcmp(n,"mad"))     return 8;
  if(!strcmp(n,"wlb"))     return 9;
  return -1;
}
static int *player_field_ptr(int i){
  switch(i){
    case 0: return &g_player.hp;
    case 1: return &g_player.energy;
    case 2: return &g_player.focus;
    case 3: return &g_player.nunchi;
    case 4: return &g_player.balls;
    case 5: return &g_player.perf;
    case 6: return &g_player.net;
    case 7: return &g_player.spec;
    case 8: return &g_player.mad;
    case 9: return &g_player.wlb;
    default: return NULL;
  }
}
static void player_stat_add(const char *n, int d){
  int i = player_stat_index(n);
  if(i >= 0 && player_field_ptr(i)){ *player_field_ptr(i) += d; return; }
  for(int k=0;k<g_player.gen_n;k++){
    if(!strcmp(g_player.gen_name[k], n)){ g_player.gen_val[k] += d; return; }
  }
  if(g_player.gen_n < 64){
    strncpy(g_player.gen_name[g_player.gen_n], n, 23);
    g_player.gen_name[g_player.gen_n][23] = 0;
    g_player.gen_val[g_player.gen_n] = d;
    g_player.gen_n++;
  }
}
static int rel_field_index(const char *n){
  if(!strcmp(n,"favor"))      return REL_FAVOR;
  if(!strcmp(n,"trust"))      return REL_TRUST;
  if(!strcmp(n,"debt"))       return REL_DEBT;
  if(!strcmp(n,"suspicion"))  return REL_SUSPICION;
  if(!strcmp(n,"influence"))  return REL_INFLUENCE;
  if(!strcmp(n,"respect"))    return REL_RESPECT;
  if(!strcmp(n,"resentment")) return REL_RESENTMENT;
  if(!strcmp(n,"loyalty"))    return REL_LOYALTY;
  return -1;
}
static int find_scene(const char *id){
  for(int i=0;i<g_nscenes;i++) if(!strcmp(g_scenes[i].name,id)) return i;
  return -1;
}
static int find_node(int si, const char *label){
  Scene *s = &g_scenes[si];
  for(int i=0;i<s->n_nodes;i++) if(!strcmp(s->nodes[i].label,label)) return i;
  return -1;
}
static Node *cur_node(Scene *s){
  return s->n_nodes > 0 ? &s->nodes[s->n_nodes-1] : NULL;
}

/* ---- loader ---- */
int dsl_load(const char *path){
  FILE *f = fopen(path, "r");
  if(!f) return 0;
  if(g_nscenes >= MAXSCENE){ fclose(f); return 0; }

  Scene *s = &g_scenes[g_nscenes];
  memset(s, 0, sizeof(*s));
  /* entry node (statements before any label) */
  s->nodes[0].label[0] = 0;
  s->n_nodes = 1;

  char line[1024];
  while(fgets(line, sizeof line, f)){
    trim(line);
    if(line[0] == 0) continue;
    if(line[0] == '#') continue;

    if(!strncmp(line, "name:", 5)){ trim(line+5); strncpy(s->name, line+5, 63); s->name[63]=0; continue; }
    if(!strncmp(line, "bg:", 3)){ continue; }

    size_t L = strlen(line);
    if(line[L-1] == ':'){
      char lab[64];
      strncpy(lab, line, L-1); lab[L-1] = 0; trim(lab);
      if(!strcmp(lab, "choice")){
        /* choice marks the current (unlabeled entry) node as choice-bearing;
         * its option lines are appended to that node below. */
        Node *cn = cur_node(s);
        if(cn) cn->is_choice = 1;
        continue;
      }
      if(s->n_nodes < MAXNODE){
        strncpy(s->nodes[s->n_nodes].label, lab, 63); s->nodes[s->n_nodes].label[63] = 0;
        s->n_nodes++;
      }
      continue;
    }

    Node *n = cur_node(s);
    if(!n) continue;

    if(n->is_choice){
      if(n->n_opt < CHOICE_CAP){
        int j = n->n_opt;
        n->opt_has_guard[j] = 0; n->opt_guard_stat[j] = -1; n->opt_guard_min[j] = 0;
        n->opt_label[j][0] = 0; n->opt_target[j][0] = 0;

        char *p = line;
        if(*p == '['){
          char *rb = strchr(p, ']');
          if(rb){
            char g[64]; strncpy(g, p+1, (size_t)(rb-p-1)); g[rb-p-1] = 0; trim(g);
            char *ge = strstr(g, ">="); int gmin = 0; char gname[32] = "";
            if(ge){ strncpy(gname, g, (size_t)(ge-g)); gname[ge-g] = 0; gmin = atoi(ge+2); }
            else { char *gt = strchr(g, '>'); if(gt){ strncpy(gname, g, (size_t)(gt-g)); gname[gt-g]=0; gmin = atoi(gt+1); } }
            trim(gname);
            n->opt_has_guard[j] = 1; n->opt_guard_stat[j] = player_stat_index(gname); n->opt_guard_min[j] = gmin;
            p = rb + 1;
          }
        }
        while(*p==' '||*p=='\t') p++;
        if(*p == '"'){ p++; char *q = strchr(p, '"'); if(q){ strncpy(n->opt_label[j], p, (size_t)(q-p)); n->opt_label[j][q-p]=0; p = q+1; } }
        char *arrow = strstr(p, "->");
        if(arrow){ char *t = arrow+2; while(*t==' '||*t=='\t') t++; trim(t); strncpy(n->opt_target[j], t, 63); n->opt_target[j][63]=0; }
        n->n_opt++;
      }
      continue;
    }

    if(n->n_stmts < MAXSTMT){
      Stmt *st = &n->stmts[n->n_stmts];
      memset(st, 0, sizeof(*st));

      if(!strncmp(line, "say", 3) && (line[3]==' '||line[3]=='\t'||line[3]==0)){
        st->type = ST_SAY;
        char *rest = line + 3; while(*rest==' '||*rest=='\t') rest++;
        char *colon = strchr(rest, ':');
        if(colon){
          char tmp[256]; strncpy(tmp, rest, (size_t)(colon-rest)); tmp[colon-rest] = 0; trim(tmp);
          if(tmp[0]!=0 && strchr(tmp,' ')==NULL){
            strncpy(st->speaker, tmp, 63); st->speaker[63]=0;
            char *tx = colon+1; while(*tx==' '||*tx=='\t') tx++; strncpy(st->text, tx, 255); st->text[255]=0;
          } else { strncpy(st->text, rest, 255); st->text[255]=0; }
        } else { strncpy(st->text, rest, 255); st->text[255]=0; }
      } else if(!strncmp(line, "rel ", 4)){
        st->type = ST_REL;
        char *a = line+4;
        char *sp = strchr(a,' '); if(sp){ *sp=0; strncpy(st->npc,a,31); st->npc[31]=0; a=sp+1; }
        sp = strchr(a,' '); if(sp){ *sp=0; strncpy(st->field,a,31); st->field[31]=0; a=sp+1; }
        st->delta = atoi(a);
      } else if(!strncmp(line, "stat ", 5)){
        st->type = ST_STAT;
        char *a = line+5;
        char *sp = strchr(a,' '); if(sp){ *sp=0; strncpy(st->field,a,31); st->field[31]=0; a=sp+1; }
        st->delta = atoi(a);
      } else if(!strncmp(line, "goto ", 5)){
        st->type = ST_GOTO; strncpy(st->target, line+5, 63); st->target[63]=0; trim(st->target);
      } else if(!strncmp(line, "flag ", 5)){
        st->type = ST_FLAG;
        char *a = line+5;
        char *sp = strchr(a, ' '); if(sp){ *sp = 0; }
        strncpy(st->flag, a, 63); st->flag[63]=0; trim(st->flag);
      } else if(!strncmp(line, "card ", 5)){
        st->type = ST_CARD;
        char *a = line+5; while(*a==' ') a++;
        if(!strncmp(a, "add ", 4)){ a += 4; while(*a==' ') a++; strncpy(st->card, a, 63); st->card[63]=0; trim(st->card); }
      } else if(!strncmp(line, "msg ", 4)){
        st->type = ST_MSG; strncpy(st->text, line+4, 255); st->text[255]=0; trim(st->text);
      } else if(!strncmp(line, "combat_start ", 13)){
        st->type = ST_COMBAT; strncpy(st->npc, line+13, 31); st->npc[31]=0; trim(st->npc);
      } else if(!strncmp(line, "schedule ", 9)){
        st->type = ST_SCHEDULE; strncpy(st->text, line+9, 255); st->text[255]=0; trim(st->text);
      } else if(!strcmp(line, "return")){
        st->type = ST_RETURN;
      } else {
        st->type = ST_SAY; st->text[0] = 0; /* unknown: ignore */
      }
      n->n_stmts++;
    }
  }

  g_nscenes++;
  fclose(f);
  return 1;
}

/* ---- execution ---- */
#define EXEC_CONT    0
#define EXEC_GOTO    1
#define EXEC_CHOICE  2
#define EXEC_RETURN  3

static int exec_stmt(Stmt *st){
  switch(st->type){
    case ST_SAY:
      if(st->speaker[0]) printf("%s: %s\n", st->speaker, st->text);
      else printf("%s\n", st->text);
      return EXEC_CONT;
    case ST_REL: {
      uint16_t id = rel_id_for_name(st->npc);
      int f = rel_field_index(st->field);
      if(f >= 0) rel_apply(id, f, st->delta);
      return EXEC_CONT;
    }
    case ST_STAT:
      player_stat_add(st->field, st->delta);
      return EXEC_CONT;
    case ST_FLAG:
      campaign_set_flag(st->flag);
      return EXEC_CONT;
    case ST_CARD:
      g_cards_added++;
      return EXEC_CONT;
    case ST_MSG:
      msg_deliver(0, st->text);
      return EXEC_CONT;
    case ST_COMBAT:
      on_combat_start(st->npc);
      return EXEC_CONT;
    case ST_SCHEDULE:
      /* scheduling hook is owned by the scheduler layer; ignored here */
      return EXEC_CONT;
    case ST_GOTO:
      g_cur_node = find_node(g_cur_scene, st->target);
      g_cur_stmt = 0;
      if(g_cur_node < 0) return EXEC_RETURN;
      return EXEC_GOTO;
    case ST_RETURN:
      return EXEC_RETURN;
  }
  return EXEC_CONT;
}

static void exec_from(void){
  if(g_cur_scene < 0) return;
  Scene *s = &g_scenes[g_cur_scene];
  while(g_cur_node >= 0 && g_cur_node < s->n_nodes){
    Node *n = &s->nodes[g_cur_node];

    int gotoed = 0;
    while(g_cur_stmt < n->n_stmts){
      Stmt *st = &n->stmts[g_cur_stmt++];
      int r = exec_stmt(st);
      if(r == EXEC_CHOICE) return;
      if(r == EXEC_RETURN) return;
      if(r == EXEC_GOTO){ gotoed = 1; break; }
    }
    if(gotoed) continue;

    if(n->is_choice){
      g_pending_choice.active   = 1;
      g_pending_choice.scene_id = s->name;
      g_pending_choice.n        = 0;
      for(int i=0;i<n->n_opt;i++){
        if(n->opt_has_guard[i] && n->opt_guard_stat[i] >= 0 && player_field_ptr(n->opt_guard_stat[i])){
          if(*player_field_ptr(n->opt_guard_stat[i]) < n->opt_guard_min[i]) continue;
        }
        ChoiceOption *d = &g_pending_choice.opt[g_pending_choice.n++];
        d->label     = n->opt_label[i];
        d->target    = n->opt_target[i];
        d->has_guard = n->opt_has_guard[i];
        d->guard_stat= n->opt_guard_stat[i];
        d->guard_min = n->opt_guard_min[i];
      }
      return; /* stop at choice */
    }

    /* non-choice node ended naturally: scene is done */
    return;
  }
}

void dsl_run_scene(const char *scene_id){
  g_pending_choice.active = 0;
  int si = find_scene(scene_id);
  if(si < 0) return;
  g_cur_scene = si;
  g_cur_node  = 0;
  g_cur_stmt  = 0;
  exec_from();
}

void dsl_choice(uint8_t idx){
  if(!g_pending_choice.active) return;
  if(idx >= (uint8_t)g_pending_choice.n) return;
  const char *target = g_pending_choice.opt[idx].target;
  g_pending_choice.active = 0;
  g_cur_node = find_node(g_cur_scene, target);
  g_cur_stmt = 0;
  if(g_cur_node < 0) return;
  exec_from();
}

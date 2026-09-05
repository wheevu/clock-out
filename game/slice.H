#ifndef CLOCKOUT_SLICE_H
#define CLOCKOUT_SLICE_H
#include "combat.H"

typedef enum { SL_TITLE, SL_OFFICE, SL_NOTE, SL_KIM, SL_COPIER,
               SL_REWARD, SL_MANAGER, SL_BOSS, SL_EXIT, SL_DEFEAT } SliceScreen;
typedef enum { SL_LEFT, SL_RIGHT, SL_UP, SL_DOWN, SL_CONFIRM,
               SL_BACK, SL_END_TURN, SL_PAUSE } SliceInput;
typedef struct {
    SliceScreen screen;
    int selected, clue, talked, cleared, paused, reduced_motion;
    int hp, reward;
    const char *notice;
} Slice;
extern Slice g_slice;
void slice_init(void);
void slice_input(SliceInput input);
void slice_dispatch(Event e);
void slice_draw(double t);
#endif

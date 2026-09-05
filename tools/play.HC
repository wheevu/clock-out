/* macOS/SDL host. The engine and input state machine remain portable .HC. */
#include <SDL.h>
#include "game/slice.H"
#include "game/cards.H"
#include "render/ui_app.H"
#include <string.h>

void ev_dispatch(Event e) { slice_dispatch(e); }
void on_combat_start(const char *name) { (void)name; }

static int keyboard(SDL_Keycode key) {
    switch(key) {
        case SDLK_a:case SDLK_LEFT:return SL_LEFT;
        case SDLK_d:case SDLK_RIGHT:return SL_RIGHT;
        case SDLK_w:case SDLK_UP:return SL_UP;
        case SDLK_s:case SDLK_DOWN:return SL_DOWN;
        case SDLK_RETURN:case SDLK_e:return SL_CONFIRM;
        case SDLK_ESCAPE:return SL_BACK;
        case SDLK_SPACE:return SL_END_TURN;
        default:return -1;
    }
}

static int controller(Uint8 button) {
    switch(button) {
        case SDL_CONTROLLER_BUTTON_DPAD_LEFT:return SL_LEFT;
        case SDL_CONTROLLER_BUTTON_DPAD_RIGHT:return SL_RIGHT;
        case SDL_CONTROLLER_BUTTON_DPAD_UP:return SL_UP;
        case SDL_CONTROLLER_BUTTON_DPAD_DOWN:return SL_DOWN;
        case SDL_CONTROLLER_BUTTON_A:return SL_CONFIRM;
        case SDL_CONTROLLER_BUTTON_B:return SL_BACK;
        case SDL_CONTROLLER_BUTTON_START:return SL_PAUSE;
        case SDL_CONTROLLER_BUTTON_Y:return SL_END_TURN;
        default:return -1;
    }
}

/* Bounded native smoke journey, injected through SDL's real keyboard queue. */
static SDL_Keycode smoke_key(void) {
    if(g_slice.paused)return SDLK_ESCAPE;
    int target=0;
    switch(g_slice.screen) {
        case SL_OFFICE:
            target=!g_slice.clue?0:!g_slice.talked?1:!g_slice.cleared?2:3;break;
        case SL_MANAGER:target=1;break;
        case SL_COPIER:case SL_BOSS:
            target=-1;
            for(int i=0;i<g_combat.hand_n;i++) {
                CardDef *c=card_by_id(g_combat.hand[i]);
                if(c&&c->cost<=g_combat.player.energy){target=i;break;}
            }
            if(target<0)return SDLK_SPACE;
            break;
        default:return SDLK_RETURN;
    }
    return g_slice.selected==target?SDLK_RETURN:SDLK_RIGHT;
}

int main(int argc,char **argv) {
    int smoke=0;
    if(argc==2 && strcmp(argv[1],"--help")==0) {
        puts("Clock Out: make play\nArrow keys: inspect/select. Enter: confirm. Space: end turn.\nEsc: pause/back. F11: fullscreen. F2: reduced effects. F3: mute.\nController: D-pad, A confirm, B back, Y end turn, Start pause.\n--smoke: play a bounded victory journey through SDL keyboard events and exit.");return 0;
    }
    if(argc==2 && strcmp(argv[1],"--smoke")==0)smoke=1;
    else if(argc!=1) { fputs("Unknown argument. Use --help.\n",stderr);return 2; }
    if(SDL_Init(SDL_INIT_VIDEO|SDL_INIT_GAMECONTROLLER)!=0) {
        fprintf(stderr,"SDL init: %s\n",SDL_GetError());return 1;
    }
    SDL_SetHint(SDL_HINT_RENDER_SCALE_QUALITY,"0");
    SDL_Window *window=SDL_CreateWindow("퇴근 / Clock Out",SDL_WINDOWPOS_CENTERED,
        SDL_WINDOWPOS_CENTERED,1280,720,SDL_WINDOW_RESIZABLE|SDL_WINDOW_ALLOW_HIGHDPI);
    SDL_Renderer *renderer=window?SDL_CreateRenderer(window,-1,SDL_RENDERER_ACCELERATED|SDL_RENDERER_PRESENTVSYNC):NULL;
    if(window&&!renderer)renderer=SDL_CreateRenderer(window,-1,SDL_RENDERER_SOFTWARE);
    SDL_Texture *texture=renderer?SDL_CreateTexture(renderer,SDL_PIXELFORMAT_RGB24,
        SDL_TEXTUREACCESS_STREAMING,RW,RH):NULL;
    int result=1;
    SDL_GameController *pad=NULL;
    SDL_AudioDeviceID audio=0;
    if(!texture) { fprintf(stderr,"Window/renderer: %s\n",SDL_GetError());goto cleanup; }
    SDL_SetWindowMinimumSize(window,RW,RH);
    SDL_RenderSetLogicalSize(renderer,RW,RH);
    SDL_RenderSetIntegerScale(renderer,SDL_TRUE);
    SDL_SetRenderDrawColor(renderer,5,9,12,255);
    for(int i=0;i<SDL_NumJoysticks()&&!pad;i++)
        if(SDL_IsGameController(i))pad=SDL_GameControllerOpen(i);
    SDL_AudioSpec want={0};
    want.freq=22050;want.format=AUDIO_S16SYS;want.channels=1;want.samples=512;
    if(SDL_InitSubSystem(SDL_INIT_AUDIO)==0)audio=SDL_OpenAudioDevice(NULL,0,&want,NULL,0);
    if(audio)SDL_PauseAudioDevice(audio,0);
    else fprintf(stderr,"Audio unavailable; continuing silently: %s\n",SDL_GetError());
    uia_init();slice_init();
    if(!ui_sprite("char_player")) {
        fputs("Missing assets. Run make play from the repository root.\n",stderr);goto cleanup;
    }
    static uint8_t rgb[RW*RH*3];
    Uint64 start=SDL_GetPerformanceCounter();
    int running=1,frames=0,muted=0;
    while(running) {
        if(smoke) {
            SDL_Event key={0};key.type=SDL_KEYDOWN;key.key.keysym.sym=smoke_key();
            SDL_PushEvent(&key);
        }
        SDL_Event e;
        while(SDL_PollEvent(&e)) {
            int action=-1;
            if(e.type==SDL_QUIT)running=0;
            if(e.type==SDL_WINDOWEVENT&&e.window.event==SDL_WINDOWEVENT_FOCUS_LOST)
                g_slice.paused=1;
            if(e.type==SDL_CONTROLLERDEVICEADDED&&!pad&&SDL_IsGameController(e.cdevice.which))
                pad=SDL_GameControllerOpen(e.cdevice.which);
            if(e.type==SDL_CONTROLLERDEVICEREMOVED&&pad&&
               SDL_JoystickInstanceID(SDL_GameControllerGetJoystick(pad))==e.cdevice.which) {
                SDL_GameControllerClose(pad);pad=NULL;g_slice.paused=1;
            }
            if(e.type==SDL_CONTROLLERBUTTONDOWN&&pad&&
               SDL_JoystickInstanceID(SDL_GameControllerGetJoystick(pad))==e.cbutton.which)
                action=controller(e.cbutton.button);
            if(e.type==SDL_KEYDOWN&&!e.key.repeat) {
                action=keyboard(e.key.keysym.sym);
                if(e.key.keysym.sym==SDLK_F2)g_slice.reduced_motion=!g_slice.reduced_motion;
                if(e.key.keysym.sym==SDLK_F3)muted=!muted;
                if(e.key.keysym.sym==SDLK_F11) {
                    Uint32 mode=(SDL_GetWindowFlags(window)&SDL_WINDOW_FULLSCREEN_DESKTOP)?0:SDL_WINDOW_FULLSCREEN_DESKTOP;
                    if(SDL_SetWindowFullscreen(window,mode)!=0)fprintf(stderr,"Fullscreen: %s\n",SDL_GetError());
                }
            }
            if(action>=0) {
                slice_input((SliceInput)action);
                if(audio&&!muted) {
                    Sint16 click[440];
                    for(int i=0;i<440;i++)click[i]=(Sint16)(((i/12)%2?1:-1)*(440-i)*2);
                    SDL_ClearQueuedAudio(audio);
                    SDL_QueueAudio(audio,click,sizeof click);
                }
            }
        }
        double t=(double)(SDL_GetPerformanceCounter()-start)/SDL_GetPerformanceFrequency();
        slice_draw(t);
        ui_frame_rgb(rgb);
        if(SDL_UpdateTexture(texture,NULL,rgb,RW*3)!=0 || SDL_RenderClear(renderer)!=0 ||
           SDL_RenderCopy(renderer,texture,NULL,NULL)!=0) {
            fprintf(stderr,"Present: %s\n",SDL_GetError());goto cleanup;
        }
        SDL_RenderPresent(renderer);
        if(smoke) {
            frames++;
            if(g_slice.screen==SL_EXIT) {
                printf("PASS SDL: title to exit via keyboard events, %d frames, RGB upload, cleanup\n",frames);
                running=0;
            } else if(frames>=500||g_slice.screen==SL_DEFEAT) {
                fputs("FAIL SDL: victory journey did not finish\n",stderr);goto cleanup;
            }
        }
        SDL_Delay(1);
    }
    result=0;
cleanup:
    if(audio)SDL_CloseAudioDevice(audio);
    if(pad)SDL_GameControllerClose(pad);
    if(texture)SDL_DestroyTexture(texture);
    if(renderer)SDL_DestroyRenderer(renderer);
    if(window)SDL_DestroyWindow(window);
    SDL_Quit();return result;
}

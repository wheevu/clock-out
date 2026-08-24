# 퇴근 (Toegeun) -- build & test
# HolyC-flavored sources (.HC). On this host we build with a C99 compiler
# (cc) since the syntax is 1:1 portable; TempleOS builds these same files
# with the HolyC compiler. Run `make check`.

CC      ?= cc
CFLAGS  ?= -x c -I. -Iinclude -O2 -Wall -Wextra
LIBS    ?= -lm
BIN     ?= bin

CORE = $(wildcard core/*.HC)
KR   = $(wildcard korean/*.HC)
REN  = $(wildcard render/*.HC)
PHY  = $(wildcard physics/*.HC)
GAME = $(wildcard game/*.HC)
NAR  = $(wildcard narrative/*.HC)
CON  = $(wildcard content/*.HC)

ALL = $(CORE) $(KR) $(REN) $(PHY) $(GAME) $(NAR) $(CON)

.PHONY: all integration check shots gif clean

all: integration

$(BIN):
	mkdir -p $(BIN)

integration: $(BIN) tests/integration_test.HC $(ALL)
	$(CC) $(CFLAGS) $(LIBS) -o $(BIN)/integration tests/integration_test.HC $(ALL)

check: integration
	@echo "=== integration ===" && ./$(BIN)/integration
	@$(CC) $(CFLAGS) $(LIBS) -o $(BIN)/pt  physics/phys.HC $(CORE) tests/physics_test.HC && ./$(BIN)/pt | tail -1
	@$(CC) $(CFLAGS) $(LIBS) -o $(BIN)/rt  render/render.HC core/math.HC tests/render_test.HC && ./$(BIN)/rt | tail -1
	@$(CC) $(CFLAGS) $(LIBS) -o $(BIN)/kt  korean/hangul.HC korean/ime.HC core/strings.HC core/math.HC tests/korean_test.HC && ./$(BIN)/kt | tail -1
	@$(CC) $(CFLAGS) $(LIBS) -o $(BIN)/gt  game/cards.HC game/combat.HC game/ai.HC physics/phys.HC $(CORE) tests/game_test.HC && ./$(BIN)/gt | tail -1
	@$(CC) $(CFLAGS) $(LIBS) -o $(BIN)/nt  narrative/*.HC $(CORE) tests/narrative_test.HC && ./$(BIN)/nt | tail -1
	@echo "=== linguist hint ===" && (command -v github-linguist >/dev/null && github-linguist 2>/dev/null || echo "HolyC sources: $(words $(ALL)) files")

# ---- visuals ----
SHOTDIR   = assets/shots
SHOTFILES = $(wildcard $(SHOTDIR)/frame_*.ppm)

shots: $(BIN)/shot
	@mkdir -p $(SHOTDIR)
	@./$(BIN)/shot
	@echo "frames written to $(SHOTDIR)"

$(BIN)/shot: $(BIN) tools/shot.HC $(ALL)
	$(CC) $(CFLAGS) $(LIBS) -o $(BIN)/shot tools/shot.HC $(ALL)

gif: shots
	@mkdir -p $(SHOTDIR)
	@python3 tools/asm_gif.py

clean:
	rm -rf $(BIN)

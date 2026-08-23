/* campaign.h -- act/flag state machine for the overall story. */
#ifndef CAMPAIGN_H
#define CAMPAIGN_H

#define CAMPAIGN_FLAG_CAP 128

void campaign_init(void);
void campaign_set_flag(const char *f);      /* sets flag (idempotent) */
int  campaign_has_flag(const char *f);      /* 1 if set else 0 */
void campaign_clear_flag(const char *f);
void campaign_tick(void);   /* recompute act from key flags */
int  campaign_act(void);    /* current act number (1-based) */

#endif /* CAMPAIGN_H */

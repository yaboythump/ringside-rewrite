// The top screen: a live view of the funeral home.
#ifndef SCENE_H
#define SCENE_H

#include <stdbool.h>

void scene_init(void);
void scene_start_service(void);
void scene_start_leaving(void);
bool scene_all_seated(void);
bool scene_all_gone(void);
void scene_update(void);
void scene_draw(void);

#endif

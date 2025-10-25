#pragma once

#include <stddef.h>
#include <stdint.h>

void listener_init(void);
void listener_shutdown(void);
void listener_tick(void);

int listener_poll_byte(void);
// TODO: sizeof size_t in real mode? i.e. should fit into a single register
void listener_send(uint8_t const* buffer, size_t count);

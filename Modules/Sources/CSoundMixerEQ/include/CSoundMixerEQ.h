#ifndef C_SOUND_MIXER_EQ_H
#define C_SOUND_MIXER_EQ_H
#include <stddef.h>
#include <stdbool.h>
#include <AudioToolbox/AudioToolbox.h>

typedef struct OSEQState OSEQState;
typedef struct { unsigned firstChannel; unsigned channelCount; } OSEQOutputRange;
OSEQState *OSEQCreate(double sampleRate, unsigned channels);
/// Immutable output ranges are copied before rendering. Invalid/overlapping ranges return NULL.
OSEQState *OSEQCreateRouted(double sampleRate, unsigned channels, const OSEQOutputRange *ranges,
                          unsigned rangeCount, unsigned totalOutputChannels);
void OSEQDestroy(OSEQState *state);
/// Single control-thread writer. Coefficients are ten normalized b0,b1,b2,a1,a2 stages.
void OSEQPublish(OSEQState *state, const double *coefficients);
void OSEQSetGain(OSEQState *state, float gain);
float OSEQGetGain(OSEQState *state);
bool OSEQSawAudio(OSEQState *state);
void OSEQRetire(OSEQState *state);
void OSEQProcessInterleaved(OSEQState *state, float *samples, size_t frames, unsigned channels);
void OSEQProcessPlanar(OSEQState *state, float *left, float *right, size_t frames);
/// The IOProc entry point: no Swift runtime, heap allocation, or locks.
void OSEQProcessAudioBuffers(OSEQState *state, const AudioBufferList *input, AudioBufferList *output);
#endif

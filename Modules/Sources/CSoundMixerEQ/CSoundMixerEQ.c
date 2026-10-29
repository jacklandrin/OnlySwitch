#include "CSoundMixerEQ.h"
#include <stdatomic.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

_Static_assert(ATOMIC_INT_LOCK_FREE == 2, "EQ requires lock-free 32-bit atomics");
_Static_assert(ATOMIC_LLONG_LOCK_FREE == 2, "EQ requires lock-free 64-bit atomics");
enum { bands = 10, coefficientCount = 50, transitionFrames = 256 };
typedef struct { double coefficients[coefficientCount]; double delay[2][bands][2]; } FilterBank;
struct OSEQState {
    _Atomic unsigned revision;
    _Atomic unsigned long long published[coefficientCount];
    _Atomic unsigned gainBits;
    _Atomic unsigned retired;
    _Atomic unsigned heard;
    unsigned seenRevision, activeBank, transition;
    unsigned channels;
    float currentGain;
    FilterBank banks[2];
    unsigned routeCount, totalOutputChannels;
    OSEQOutputRange routes[16];
};

static unsigned floatBits(float value) { unsigned bits; memcpy(&bits, &value, sizeof(bits)); return bits; }
static float bitsFloat(unsigned value) { float result; memcpy(&result, &value, sizeof(result)); return result; }
static unsigned long long doubleBits(double value) { unsigned long long bits; memcpy(&bits, &value, sizeof(bits)); return bits; }
static double bitsDouble(unsigned long long value) { double result; memcpy(&result, &value, sizeof(result)); return result; }

OSEQState *OSEQCreate(double sampleRate, unsigned channels) {
    if (!isfinite(sampleRate) || sampleRate <= 0 || channels < 1 || channels > 2) return NULL;
    OSEQState *state = calloc(1, sizeof(OSEQState));
    if (!state) return NULL;
    state->channels = channels;
    state->currentGain = 1;
    atomic_init(&state->revision, 0);
    atomic_init(&state->gainBits, floatBits(1));
    atomic_init(&state->retired, 0);
    atomic_init(&state->heard, 0);
    for (unsigned i = 0; i < coefficientCount; ++i) {
        double value = i % 5 == 0 ? 1 : 0;
        state->banks[0].coefficients[i] = value;
        state->banks[1].coefficients[i] = value;
        atomic_init(&state->published[i], doubleBits(value));
    }
    return state;
}
OSEQState *OSEQCreateRouted(double sampleRate, unsigned channels, const OSEQOutputRange *ranges,
                          unsigned rangeCount, unsigned totalOutputChannels) {
    if (!ranges || !rangeCount || rangeCount > 16 || !totalOutputChannels || totalOutputChannels > 1024) return NULL;
    for (unsigned i = 0; i < rangeCount; ++i) {
        OSEQOutputRange range = ranges[i];
        if (!range.channelCount || range.channelCount > 64 || range.firstChannel >= totalOutputChannels
            || range.channelCount > totalOutputChannels - range.firstChannel) return NULL;
        for (unsigned j = 0; j < i; ++j) {
            OSEQOutputRange previous = ranges[j];
            if (range.firstChannel < previous.firstChannel + previous.channelCount
                && previous.firstChannel < range.firstChannel + range.channelCount) return NULL;
        }
    }
    OSEQState *state = OSEQCreate(sampleRate, channels);
    if (!state) return NULL;
    state->routeCount = rangeCount;
    state->totalOutputChannels = totalOutputChannels;
    memcpy(state->routes, ranges, rangeCount * sizeof(OSEQOutputRange));
    return state;
}
void OSEQDestroy(OSEQState *state) { free(state); }
void OSEQPublish(OSEQState *state, const double *coefficients) {
    if (!state || !coefficients) return;
    // All payload slots are atomic too: the bounded seqlock reader never races a writer.
    atomic_fetch_add_explicit(&state->revision, 1, memory_order_seq_cst);
    for (unsigned i = 0; i < coefficientCount; ++i)
        atomic_store_explicit(&state->published[i], doubleBits(coefficients[i]), memory_order_seq_cst);
    atomic_fetch_add_explicit(&state->revision, 1, memory_order_seq_cst);
}
void OSEQSetGain(OSEQState *state, float gain) {
    if (state) atomic_store_explicit(&state->gainBits, floatBits(isfinite(gain) ? fminf(1, fmaxf(0, gain)) : 1), memory_order_relaxed);
}
float OSEQGetGain(OSEQState *state) { return state ? bitsFloat(atomic_load_explicit(&state->gainBits, memory_order_relaxed)) : 1; }
bool OSEQSawAudio(OSEQState *state) { return state && atomic_load_explicit(&state->heard, memory_order_relaxed); }
void OSEQRetire(OSEQState *state) { if (state) atomic_store_explicit(&state->retired, 1, memory_order_release); }

static void acceptUpdate(OSEQState *state) {
    if (state->transition) return;
    unsigned before = atomic_load_explicit(&state->revision, memory_order_seq_cst);
    if ((before & 1) || before == state->seenRevision) return;
    double snapshot[coefficientCount];
    for (unsigned i = 0; i < coefficientCount; ++i)
        snapshot[i] = bitsDouble(atomic_load_explicit(&state->published[i], memory_order_seq_cst));
    unsigned after = atomic_load_explicit(&state->revision, memory_order_seq_cst);
    if (before != after) return; // Keep the previous complete revision, without retrying or waiting.
    FilterBank *next = &state->banks[1 - state->activeBank];
    memcpy(next->coefficients, snapshot, sizeof(snapshot));
    memcpy(next->delay, state->banks[state->activeBank].delay, sizeof(next->delay));
    state->seenRevision = after;
    state->transition = transitionFrames;
}
static double filter(FilterBank *bank, double sample, unsigned channel) {
    double value = sample;
    for (unsigned band = 0; band < bands; ++band) {
        const double *c = &bank->coefficients[band * 5];
        double *d = bank->delay[channel][band];
        double result = c[0] * value + d[0];
        double z1 = c[1] * value - c[3] * result + d[1];
        double z2 = c[2] * value - c[4] * result;
        if (!isfinite(result) || !isfinite(z1) || !isfinite(z2)) { result = 0; z1 = 0; z2 = 0; }
        d[0] = fabs(z1) < 1e-30 ? 0 : z1;
        d[1] = fabs(z2) < 1e-30 ? 0 : z2;
        value = result;
    }
    return value;
}
static void frame(OSEQState *state, const float *input, float *output, unsigned channels, float gain) {
    double mix = state->transition ? 1.0 - (double)state->transition / transitionFrames : 0;
    for (unsigned channel = 0; channel < channels; ++channel) {
        double x = isfinite(input[channel]) ? input[channel] : 0;
        if (x != 0) atomic_store_explicit(&state->heard, 1, memory_order_relaxed);
        double y = filter(&state->banks[state->activeBank], x, channel);
        if (state->transition) {
            double next = filter(&state->banks[1 - state->activeBank], x, channel);
            y += (next - y) * mix;
        }
        // Bound boost overshoot at the output, after applying the user's gain.
        y *= gain;
        output[channel] = isfinite(y) ? (float)fmin(1, fmax(-1, y)) : 0;
    }
    if (state->transition && --state->transition == 0) state->activeBank = 1 - state->activeBank;
}
static bool begin(OSEQState *state) {
    if (!state || atomic_load_explicit(&state->retired, memory_order_acquire)) return false;
    acceptUpdate(state);
    return true;
}
void OSEQProcessInterleaved(OSEQState *state, float *samples, size_t frames, unsigned channels) {
    if (!samples || !begin(state) || channels != state->channels) return;
    float target = OSEQGetGain(state), start = state->currentGain;
    for (size_t i = 0; i < frames; ++i) {
        float gain = start + (target - start) * (float)(i + 1) / (float)frames;
        frame(state, samples + i * channels, samples + i * channels, channels, gain);
    }
    state->currentGain = target;
}
void OSEQProcessPlanar(OSEQState *state, float *left, float *right, size_t frames) {
    if (!left || !right || !begin(state) || state->channels != 2) return;
    float target = OSEQGetGain(state), start = state->currentGain;
    for (size_t i = 0; i < frames; ++i) {
        float input[2] = { left[i], right[i] }, output[2];
        float gain = start + (target - start) * (float)(i + 1) / (float)frames;
        frame(state, input, output, 2, gain);
        left[i] = output[0]; right[i] = output[1];
    }
    state->currentGain = target;
}

// Describe either stereo interleaved or mono/dual-mono planar buffers without a heap conversion.
static unsigned channelsFor(const AudioBufferList *list, float **channels, unsigned *strides, size_t *frames) {
    unsigned channel = 0;
    *frames = SIZE_MAX;
    for (unsigned buffer = 0; buffer < list->mNumberBuffers; ++buffer) {
        const AudioBuffer *b = &list->mBuffers[buffer];
        if (!b->mData || b->mNumberChannels == 0 || b->mNumberChannels > 64) return 0;
        if (channel >= 2) continue;
        size_t available = b->mDataByteSize / sizeof(float) / b->mNumberChannels;
        if (available < *frames) *frames = available;
        for (unsigned c = 0; c < b->mNumberChannels && channel < 2; ++c) {
            channels[channel] = (float *)b->mData + c;
            strides[channel++] = b->mNumberChannels;
        }
    }
    return channel;
}
typedef struct { float *data; unsigned stride; size_t frames; } OutputChannel;
static bool outputChannel(const AudioBufferList *list, unsigned globalChannel, OutputChannel *result) {
    unsigned first = 0;
    for (unsigned i = 0; i < list->mNumberBuffers; ++i) {
        const AudioBuffer *buffer = &list->mBuffers[i];
        if (!buffer->mData || !buffer->mNumberChannels || buffer->mNumberChannels > 64) return false;
        if (globalChannel >= first && globalChannel - first < buffer->mNumberChannels) {
            result->data = (float *)buffer->mData + globalChannel - first;
            result->stride = buffer->mNumberChannels;
            result->frames = buffer->mDataByteSize / sizeof(float) / buffer->mNumberChannels;
            return true;
        }
        first += buffer->mNumberChannels;
    }
    return false;
}
static void processRouted(OSEQState *state, const AudioBufferList *input, AudioBufferList *output) {
    unsigned totalChannels = 0;
    if (output->mNumberBuffers > 1024) return;
    for (unsigned i = 0; i < output->mNumberBuffers; ++i) {
        unsigned count = output->mBuffers[i].mNumberChannels;
        if (!count || count > 64 || totalChannels > 1024 - count) return;
        totalChannels += count;
    }
    if (totalChannels != state->totalOutputChannels) return;
    float *inputChannels[2]; unsigned inputStrides[2]; size_t frames;
    if (channelsFor(input, inputChannels, inputStrides, &frames) != 2) return;
    OutputChannel destinations[16][2];
    for (unsigned route = 0; route < state->routeCount; ++route) {
        OSEQOutputRange range = state->routes[route];
        if (!outputChannel(output, range.firstChannel, &destinations[route][0])) return;
        if (range.channelCount > 1 && !outputChannel(output, range.firstChannel + 1, &destinations[route][1])) return;
    }
    float target = OSEQGetGain(state), start = state->currentGain;
    for (size_t i = 0; i < frames; ++i) {
        float values[2] = { inputChannels[0][i * inputStrides[0]], inputChannels[1][i * inputStrides[1]] }, result[2];
        float gain = start + (target - start) * (float)(i + 1) / (float)frames;
        frame(state, values, result, 2, gain);
        for (unsigned route = 0; route < state->routeCount; ++route) {
            OutputChannel left = destinations[route][0];
            if (state->routes[route].channelCount == 1) {
                if (i < left.frames) left.data[i * left.stride] = (result[0] + result[1]) * 0.5f;
            } else {
                OutputChannel right = destinations[route][1];
                if (i < left.frames) left.data[i * left.stride] = result[0];
                if (i < right.frames) right.data[i * right.stride] = result[1];
            }
        }
    }
    state->currentGain = target;
}
void OSEQProcessAudioBuffers(OSEQState *state, const AudioBufferList *input, AudioBufferList *output) {
    if (!output) return;
    // Zero every byte first, including unused streams and mismatched trailing frames.
    for (unsigned i = 0; i < output->mNumberBuffers; ++i)
        if (output->mBuffers[i].mData) memset(output->mBuffers[i].mData, 0, output->mBuffers[i].mDataByteSize);
    if (!input || !begin(state)) return;
    if (state->routeCount) { processRouted(state, input, output); return; }
    float *inChannels[2], *outChannels[2]; unsigned inStrides[2], outStrides[2]; size_t inFrames, outFrames;
    if (channelsFor(input, inChannels, inStrides, &inFrames) != 2) return;
    unsigned outputChannels = channelsFor(output, outChannels, outStrides, &outFrames);
    if (!outputChannels) return;
    size_t frames = inFrames < outFrames ? inFrames : outFrames;
    float target = OSEQGetGain(state), start = state->currentGain;
    for (size_t i = 0; i < frames; ++i) {
        float values[2] = { inChannels[0][i * inStrides[0]], inChannels[1][i * inStrides[1]] }, result[2];
        float gain = start + (target - start) * (float)(i + 1) / (float)frames;
        frame(state, values, result, 2, gain);
        outChannels[0][i * outStrides[0]] = outputChannels == 1 ? (result[0] + result[1]) * 0.5f : result[0];
        if (outputChannels > 1) outChannels[1][i * outStrides[1]] = result[1];
    }
    state->currentGain = target;
}

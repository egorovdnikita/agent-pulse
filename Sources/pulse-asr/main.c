// Помощник диктовки: считает текст из звука в своём процессе и завершается, когда приложение закрывает stdin.
// Отдельный процесс нужен ради памяти: модель занимает 350–650 MB, и только конец процесса отдаёт их системе.
// Микрофона, сети и файлов, кроме модели, здесь нет: звук приходит от приложения по stdin.
//
// Протокол. Запуск: pulse-asr <папка модели>. Модель загрузилась — строка "ready".
// Запрос: uint32 (little-endian) — число сэмплов, затем float32 моно 16 kHz. Ответ — одна строка текста.
#include "c-api.h"
#include <dlfcn.h>
#include <mach-o/dyld.h>
#include <libgen.h>
#include <limits.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

enum { sampleRate = 16000, featureDim = 64, threads = 2, maxSamples = sampleRate * 120 };

static int readAll(void *buffer, size_t size) {
    char *cursor = buffer;
    while (size > 0) {
        ssize_t got = read(STDIN_FILENO, cursor, size);
        if (got <= 0) return 0;
        cursor += got;
        size -= (size_t)got;
    }
    return 1;
}

// Библиотеки подгружаются на ходу: без рантайма проект собирается, а приложение честно скажет об ошибке.
static void *openRuntime(void) {
    char path[PATH_MAX];
    uint32_t size = sizeof path;
    if (_NSGetExecutablePath(path, &size) != 0) return NULL;
    char real[PATH_MAX];
    if (!realpath(path, real)) return NULL;
    char library[PATH_MAX];
    snprintf(library, sizeof library, "%s/../Frameworks/libsherpa-onnx-c-api.dylib", dirname(real));
    return dlopen(library, RTLD_NOW | RTLD_LOCAL);
}

#define SYMBOL(name) __typeof__(&name) p##name = (__typeof__(&name))dlsym(runtime, #name); if (!p##name) return 3

int main(int argc, char **argv) {
    if (argc != 2) return 2;
    void *runtime = openRuntime();
    if (!runtime) {
        fprintf(stderr, "runtime: %s\n", dlerror());
        return 3;
    }
    SYMBOL(SherpaOnnxCreateOfflineRecognizer);
    SYMBOL(SherpaOnnxCreateOfflineStream);
    SYMBOL(SherpaOnnxAcceptWaveformOffline);
    SYMBOL(SherpaOnnxDecodeOfflineStream);
    SYMBOL(SherpaOnnxGetOfflineStreamResult);
    SYMBOL(SherpaOnnxDestroyOfflineRecognizerResult);
    SYMBOL(SherpaOnnxDestroyOfflineStream);

    char encoder[PATH_MAX], decoder[PATH_MAX], joiner[PATH_MAX], tokens[PATH_MAX];
    snprintf(encoder, sizeof encoder, "%s/encoder.int8.onnx", argv[1]);
    snprintf(decoder, sizeof decoder, "%s/decoder.onnx", argv[1]);
    snprintf(joiner, sizeof joiner, "%s/joiner.onnx", argv[1]);
    snprintf(tokens, sizeof tokens, "%s/tokens.txt", argv[1]);

    SherpaOnnxOfflineRecognizerConfig config;
    memset(&config, 0, sizeof config);
    config.feat_config.sample_rate = sampleRate;
    config.feat_config.feature_dim = featureDim;
    config.model_config.transducer.encoder = encoder;
    config.model_config.transducer.decoder = decoder;
    config.model_config.transducer.joiner = joiner;
    config.model_config.tokens = tokens;
    config.model_config.num_threads = threads;
    config.model_config.provider = "cpu";
    config.model_config.model_type = "nemo_transducer";
    config.decoding_method = "greedy_search";

    const SherpaOnnxOfflineRecognizer *recognizer = pSherpaOnnxCreateOfflineRecognizer(&config);
    if (!recognizer) return 4;
    puts("ready");
    fflush(stdout);

    uint32_t count;
    while (readAll(&count, sizeof count)) {
        if (count == 0 || count > maxSamples) return 5;
        float *samples = malloc(count * sizeof(float));
        if (!samples || !readAll(samples, count * sizeof(float))) return 5;
        const SherpaOnnxOfflineStream *stream = pSherpaOnnxCreateOfflineStream(recognizer);
        pSherpaOnnxAcceptWaveformOffline(stream, sampleRate, samples, (int32_t)count);
        pSherpaOnnxDecodeOfflineStream(recognizer, stream);
        const SherpaOnnxOfflineRecognizerResult *result = pSherpaOnnxGetOfflineStreamResult(stream);
        // Ответ — одна строка: переводы строк в тексте не должны ломать протокол.
        for (char *c = (char *)result->text; c && *c; c++) if (*c == '\n' || *c == '\r') *c = ' ';
        puts(result->text ? result->text : "");
        fflush(stdout);
        pSherpaOnnxDestroyOfflineRecognizerResult(result);
        pSherpaOnnxDestroyOfflineStream(stream);
        free(samples);
    }
    return 0;
}

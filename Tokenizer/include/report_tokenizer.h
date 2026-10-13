#ifndef REPORT_TOKENIZER_H
#define REPORT_TOKENIZER_H
#include <stdint.h>
#include <stddef.h>
int32_t report_tokenizer_count(const uint8_t *input, size_t length, size_t *cl100k, size_t *o200k);
#endif

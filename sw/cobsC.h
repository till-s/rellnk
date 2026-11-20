/**LB-MIT
 *
 * MIT License
 *
 * Copyright (c) 2026 Till Straumann
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 *
 **LE-MIT*/

#pragma once

#ifdef __cplusplus
extern "C" {
#endif

#include <stdint.h>
#include <stddef.h>
#include <assert.h>

#define COBSC_EOF 0x00

typedef struct CobsCEncoderCtx {
	uint8_t        *dst;
	size_t          dstSize;
	size_t          dstIndex;
	const uint8_t  *src;
	size_t          srcSize;
	size_t          srcIndex;
	size_t          runLength;
} CobsCEncoderCtx;

static inline void
cobsCEncodeContinue(CobsCEncoderCtx *ctx)
{
	assert( ctx->runLength < 2 );
	/* continue/reposition after encoded buffer was flushed but
	 * we want to keep encoding to the same frame; must have
	 * flushed and runLength was 1 or 0.
	 */
	if ( 1 == ctx->runLength ) {
		ctx->dst[0]   = 1;
	}
	ctx->dstIndex = ctx->runLength;
}

static inline void
cobsCEncodeRewind(CobsCEncoderCtx *ctx)
{
	ctx->srcIndex  = 0;
	ctx->dstIndex  = 0;
	ctx->runLength = 0;
}

static inline void
cobsCEncodeInit(CobsCEncoderCtx *ctx)
{
	/* buffers + sizes must be set by user */
	cobsCEncodeRewind(ctx);
}

/* The encoder ensures there is space to call this
 * routine *once*; after that either cobsCEncode()
 * must be called (to append more data) and/or the buffer
 * flushed if cobsCEncode() returns zero or right away.
 *
 * e.g.,:
 *
 *    cobsCEncodeAppendEOF(&ctx);
 *    flush( ctx.dst, ctx.dstIndex);
 *    cobsCEncodeRewind(&ctx);
 */
static inline void
cobsCEncodeAppendEOF(CobsCEncoderCtx *ctx)
{
	ctx->dst[ctx->dstIndex] = COBSC_EOF;
	++ctx->dstIndex;
	ctx->runLength = 0;
}


/* Convenience wrapper:
 *   1. append more data (data,size) to a frame; routime may be
 *      called multiple times (wrap == 0).
 *   2. wrapup an exising frame; append EOF and send.
 *
 * 1. and 2. may be combined (size > 0, wrap != 0) or used
 * separately (size or wrap may be zero).
 *
 * If 'flush' returns a negative error this is propagated
 * to the caller (leaving the context as it was before
 * the flush was attempted).
 *
 * Note that the intermediate buffer ctx->dst/ctx->dstSize must
 * be managed/provided by the caller.
 */

#define COBSC_ENCODE_WRAP 1
#define COBSC_ENCODE_NO_WRAP 0
int
cobsCEncodeAddToFrame(
	CobsCEncoderCtx *ectx,
	const uint8_t *data,
	size_t size,
	int wrap,
	int (*flush)(const uint8_t *, size_t, void *closure),
	void *closure);

/* Encode the 'src' buffer into the 'dst' buffer.
 * Encoding may stop either because the source is exhausted
 * or the destination is full.
 * The reason is reflected in the return value: 1 if the
 * source is exhausted and 0 if the destination buffer is full.
 * Note that 'full' means that another segment migth not fit.
 * The encoder stops at a segment boundary and returns 0
 * leaving some of the source unconsumed.
 * In either case, encoding may proceed:
 *  1. if the destination was full then flush the destination
 *     buffer to the transmitter and 'continue' the encoder state:
 *
 *         while ( ! cobsCEncode(ctx) ) {
 *            flush(ctx->dst, cts->dstIndex);
 *            cobsCEncodeContinue(ctx);
 *         }
 *
 *  2. if the source is exhausted then
 *     a. the source buffer can be refilled or
 *        changed and encoding resumed.
 *     b. eventually, an EOF may be appended
 *        (the encoder ensures there is space in the
 *        destination buffer), the destination
 *        flushed and rewound.
 *
 *     Using an 'iovec'-style array:
 *
 *         cobsCEncodeInit(ctx);
 *         for ( n = 0; n < NUM_IOVS; ++n ) {
 *            ctx->src     = iov[n].buf;
 *            ctx->srcSize = iov[n].size;
 *            while ( ! cobsCEncode(ctx) ) {
 *               flush(ctx->dst, cts->dstIndex);
 *               cobsCEncodeContinue(ctx);
 *            }
 *         }
 *         ctx->dst[ctx->dstIndex++] = COBSC_EOF;
 *         flush(ctx->dst, ctx->dstIndex);
 *         cobsCEncodeRewind(ctx);
 */

int cobsCEncode(CobsCEncoderCtx *ctx);

typedef struct CobsCDecoderCtx {
	uint8_t        *dst;
    size_t          dstSize;
    size_t          dstIndex;
	const uint8_t  *src;
    size_t          srcSize;
    size_t          srcIndex;
	size_t          runLength;
	int             replace;
} CobsCDecoderCtx;

static inline void
cobsCDecodeContinue(CobsCDecoderCtx *ctx)
{
	ctx->srcIndex  = 0;
	ctx->dstIndex  = 0;
}

static inline void
cobsCDecodeRewind(CobsCDecoderCtx *ctx)
{
	ctx->srcIndex  = 0;
	ctx->dstIndex  = 0;
	ctx->runLength = 0;
	ctx->replace   = 0;
}

static inline void
cobsCDecodeInit(CobsCDecoderCtx *ctx)
{
	cobsCDecodeRewind(ctx);
}

/* Returns:
 *   1 when an EOF has been detected; the EOF is removed from
 *     the source but not added to the destination.
 *  -1 when no progress has been made (no source data consumed
 *     due to lack of destination space).
 *   0 otherwise the user has to check srcIndex and dstIndex
 *     to find out whether the source or destination (or both)
 *     are exhausted.
 *
 * Note that source data may be consumed even with no destination
 * space available (e.g., to remove EOF or contination bytes).
 */
int cobsCDecode(CobsCDecoderCtx *ctx);

/*
 * Decode a frame into a buffer (or continue doing so).
 * An EOF condition can be detected by the routine returning
 * a value greater than zero.
 *
 * If 'fill' fails with a negative error status then this status
 * is propagated to the caller. 'ctx->dstIndex' reflects the
 * amount of data already decoded.
 *
 * Note that the intermediate buffer ctx->src/ctx->srcSize must
 * be managed/provided by the caller.
 *
 */
int cobsCDecodeFromFrame(
	CobsCDecoderCtx *ctx,
	uint8_t *buf,
	size_t size,
	int fill(uint8_t *, size_t, void *closure),
	void *closure);

#ifdef __cplusplus
}
#endif

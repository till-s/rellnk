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

#include <cobsC.h>

#include <string.h>
#include <stdio.h>
#include <errno.h>

#define RUN_MAX  0xff

/* max segment size: header + 254 + EOF */
#define SEG_MAX  256

int
cobsCEncode(CobsCEncoderCtx *ctx)
{
	/* when a run is started the encoder ensures there is space for
	 * one max. segment + a terminating EOF, i.e., 256 bytes;
	 * thus, if there are remaining data there must be space
	 * in the buffer.
	 */
	const uint8_t *srcp;
	uint8_t       *dstp;
	const uint8_t *srcend;
	uint8_t       *dstend;
	uint8_t       *lenp;
	size_t         runLength;
	size_t         runMax;

	assert( ctx->dstSize >= SEG_MAX );

	srcp   = ctx->src + ctx->srcIndex;
	dstp   = ctx->dst + ctx->dstIndex;
	srcend = ctx->src + ctx->srcSize;
	dstend = ctx->dst + ctx->dstSize - SEG_MAX;

	if ( srcp == srcend ) {
		/* no work */
		return 1;
	}

	runLength  = ctx->runLength;

	while ( (dstp - runLength <= dstend) && (srcp < srcend) ) {
		/* remember where to store next link
		 *  - when a segment was ended by a EOF then this is the link field
		 *    but runLength + dstp have already been incremented past the EOF
		 *  - when a segment ended due to max-run then the link field is
		 *    past the end of the segment; dstp + runLength have not been
		 *    incremented
		 * in both cases destp-runLength points to the correct location
		 */
		lenp = dstp - runLength;
		if ( 0 == runLength ) {
			/* need header */
			runLength = 1;
			++dstp;
		}
		runMax = (srcend - srcp) + runLength;
		if ( runMax > RUN_MAX ) {
			runMax = RUN_MAX;
		}
		/* initially, runMax > runLength because srcp < srcend was tested above and before hitting 'again' */
		while ( COBSC_EOF != (*dstp++ = *srcp++) ) {
			if ( ++runLength >= runMax ) {
				/* source exhausted or max segment reached or both */
				/* store link */
				*lenp = runLength;
				if ( RUN_MAX == runLength ) {
					/* need a new header */
					runLength = 0;
					/* else fall through and break outer loop */
				}
				/* if runLength < RUN_MAX then source is surely exhausted */
				goto continue_outer_loop;
			}
		}
		*lenp     = runLength;
		runLength = 1;
continue_outer_loop:
		if ( 0 ) {
			/* empty statement to avoid 'label at end of compound statement' warning */
		}
	}
	ctx->srcIndex  = srcp - ctx->src;
	ctx->dstIndex  = dstp - ctx->dst;
	ctx->runLength = runLength;
	/* record the run-length */
	*(dstp - runLength) = runLength;
	if ( srcp < srcend ) {
		/* strip the space that was reserved for the next link header (in
		 * case the loop was broken due to *dst == COBSC_EOF)
		 * NOTE: if srcp<srcend the runLength may only be 0 or 1
		 * 'continue_outer_loop' can only be reached with runLength != 1 if
		 * runLength >= runMax; if srcp<srcend then runLength must have been
		 * RUN_MAX and subsequently => runLength = 0
		 */
		ctx->dstIndex -= runLength;
		return 0;
	}
	/* srcp == srcend */
	/* ctx->srcIndex = 0; prepare for new source */
	return 1;
}

int cobsCDecode(CobsCDecoderCtx *ctx)
{
	const uint8_t *srcp;
	uint8_t       *dstp;
	const uint8_t *srcend;
	uint8_t       *dstend;
	uint8_t        val;
	size_t         runLength;
	int            retVal = 0;
	size_t         newIndex;

	srcp      = ctx->src + ctx->srcIndex;
	dstp      = ctx->dst + ctx->dstIndex;
	srcend    = ctx->src + ctx->srcSize;
	dstend    = ctx->dst + ctx->dstSize;
	runLength = ctx->runLength;

	while ( srcp < srcend ) {
		if ( COBSC_EOF == (val = *srcp++) ) {
			retVal = 1;
			break;
		}
		if ( 0 == runLength ) {
			/*printf("runlength = 0; replace was %i, new runLength %d\n", ctx->replace, val); */
			if ( ctx->replace ) {
				if ( dstp >= dstend ) {
					/* no space ! */
					--srcp; /* don't consume! */
					break;
				}
				*dstp++ = 0x00;
			}
			ctx->replace = (RUN_MAX != (runLength = val));
			/*printf("replace now %i\n", ctx->replace); */
		} else {
			if ( dstp >= dstend ) {
				/* no space ! */
				--srcp; /* don't consume! */
				break;
			}
			*dstp++ = val;
		}
		runLength--;
	}
	newIndex       = srcp - ctx->src;
	if ( newIndex == ctx->srcIndex ) {
		/* no progress */
		retVal = -1;
	}
	ctx->srcIndex  = newIndex;
	ctx->dstIndex  = dstp - ctx->dst;
	ctx->runLength = runLength;
	return retVal;
}

int
cobsCEncodeAddToFrame(CobsCEncoderCtx *ectx, const uint8_t *data, size_t size, int wrap, int (*flush)(const uint8_t *, size_t, void *closure), void *closure)
{
	int status = 0;;
	if ( size ) {
		ectx->src      = data;
		ectx->srcIndex = 0;
		ectx->srcSize  = size;
		while ( ! cobsCEncode( ectx ) ) {
			if ( (status = flush( ectx->dst, ectx->dstIndex, closure )) ) {
				return status;
			}
			cobsCEncodeContinue(ectx);
		}
	}
	if ( wrap ) {
		/* space is guaranteed */
		cobsCEncodeAppendEOF(ectx);
		if ( (status = flush( ectx->dst, ectx->dstIndex, closure )) ) {
			/* remove EOF; i.e., leave state as it was if flush fails */
			ectx->dstIndex--;
			return status;
		}
		cobsCEncodeRewind(ectx);
	}
	return status;
}

int cobsCDecodeFromFrame(
	CobsCDecoderCtx *ctx,
	uint8_t *buf,
	size_t size,
	int fill(uint8_t *, size_t, void *closure),
	void *closure)
{
	int           status;
	int           eof = 0;
	size_t        remainingContent, origSrcSize;

	ctx->dst      = buf;
	ctx->dstSize  = size;
	ctx->dstIndex = 0;
	if ( 0 == ctx->srcSize ) {
		return -ENOSPC;
	}
	origSrcSize = ctx->srcSize;
	while ( ! eof ) {
		if ( ctx->srcIndex == ctx->srcSize ) {
			status = fill((uint8_t*)ctx->src, origSrcSize, closure);
			if ( status <= 0 ) {
				ctx->srcSize  = origSrcSize;
				ctx->srcIndex = origSrcSize;
				if ( 0 == status ) {
					status = -EIO;
				}
				return status;
			}
			ctx->srcSize  = status;
			ctx->srcIndex = 0;
		}
		status = cobsCDecode(ctx);
		eof    = (status > 0);
		if ( status ) {
			/* either no progress or EOF */
			break;
		}
	}

	remainingContent = ctx->srcSize - ctx->srcIndex;
	if ( remainingContent ) {
		/* must move buffer content in order to restore original srcSize */
		ctx->srcIndex = origSrcSize - remainingContent;
		memmove((void*)ctx->src, ctx->src + ctx->srcIndex, remainingContent);
	} else {
		ctx->srcIndex = origSrcSize;
	}
	ctx->srcSize = origSrcSize;

	return eof;
}

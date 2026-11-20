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
#include <stdio.h>
#include <string.h>

#undef NDEBUG
#include <assert.h>

static void
setup(uint8_t *src, size_t size, int zeroIdx)
{
	memset(src, 0xff, size);
	if ( zeroIdx >= 0) {
		src[zeroIdx] = 0x00;
	}
}

static void testSingleRun(CobsCEncoderCtx *ctx, size_t sz, int zeroIdx)
{
	int i;
	if ( zeroIdx < 0 ) {
		zeroIdx = -1;
	}
	setup((uint8_t*)ctx->src, sz, zeroIdx);
	memset(ctx->dst, 0x80, ctx->dstSize);
	ctx->srcSize = sz;
	cobsCEncodeRewind(ctx);
	assert( cobsCEncode(ctx) );
	assert( ctx->srcIndex == ctx->srcSize );
	assert( ctx->dstIndex == sz + 1 );
	if ( zeroIdx >= 0 ) {
		assert( ctx->runLength == ctx->dst[zeroIdx + 1] );
		assert( ctx->dst[0] == zeroIdx + 1 );
	} else {
		assert( ctx->runLength == 254 == sz ? 0 : sz + 1 );
		assert( ctx->dst[0] == sz + 1 );
	}
	for ( i = 0; i < sz; ++i ) {
		if ( i == zeroIdx ) {
			assert( ctx->dst[i + 1] + zeroIdx + 1 == sz + 1 );
	 	} else {
			assert( ctx->dst[i + 1] == 0xff );
		}
	}
}

static void testMultiRun(size_t dstsz, size_t srcsz, int *zeros)
{
	uint8_t         dst[srcsz*2];
	uint8_t         src[srcsz];
	CobsCEncoderCtx ctx;
	size_t          dstl, runl, i,k;
	memset(dst, 0x80, srcsz*2);
	memset(src, 0xfc, srcsz);
	for ( i = 0; zeros[i] >= 0 && zeros[i] < srcsz; ++i ) {
		src[zeros[i]] = 0x00;
	}
	cobsCEncodeInit(&ctx);
	ctx.dst     = dst;
	ctx.dstSize = dstsz;
	ctx.src     = src;
	ctx.srcSize = srcsz;
	while ( ! cobsCEncode( &ctx ) ) {
		ctx.dst += ctx.dstIndex;
		cobsCEncodeContinue(&ctx);
	}
	dstl = ctx.dstIndex + (ctx.dst - dst);
	runl = 0;
	for ( i = k = 0; i < dstl; ++i ) {
		if ( 0 == runl ) {
			runl = dst[i];
			assert( 0 != runl );
		} else {
			assert(0xfc == dst[i]);
		}
		runl--;
	}
}

int
main(int argc, char **argv)
{
	uint8_t dst[1024];
	uint8_t src[1024];
	int     zer[100];
	CobsCEncoderCtx ctx;
	cobsCEncodeInit(&ctx);
	ctx.dst     = dst;
	ctx.dstSize = sizeof(dst);
	ctx.src     = src;
	ctx.srcSize = sizeof(src);

	testSingleRun(&ctx, 1, -1);
	testSingleRun(&ctx, 1,  0);
	testSingleRun(&ctx, 254, -1);
	testSingleRun(&ctx, 254, 254);
	testSingleRun(&ctx, 254, 0);
	testSingleRun(&ctx, 254, 10);

	ctx.dstSize = 256;

	testSingleRun(&ctx, 1, -1);
	testSingleRun(&ctx, 1,  0);
	testSingleRun(&ctx, 254, -1);
	testSingleRun(&ctx, 254, 254);

	zer[0]=0; zer[1]=-1;
	testMultiRun(256, 254, zer);

	zer[0]=10; zer[1]=-1;
	testMultiRun(256, 254, zer);

	zer[0]=-1;
	testMultiRun(256, 1000, zer);

	printf("Test Passed\n");
	return 0;
}

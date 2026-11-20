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

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <vector>

#undef   NDEBUG
#include <assert.h>

using V = std::vector<uint8_t>;

struct DecoderFlusher {
	V               *enc;
	CobsCDecoderCtx *dctx;
	size_t          *premain;

	DecoderFlusher(CobsCDecoderCtx *c, size_t *p, V *v) : enc(v), dctx(c), premain(p) {}
};

int
decodeSeg(DecoderFlusher *d)
{
	int rv = 0;
	CobsCDecoderCtx *dctx = d->dctx;

	if ( *d->premain < dctx->dstSize ) {
		dctx->dstSize = *d->premain;
	}

	while ( !rv && dctx->srcIndex < dctx->srcSize ) {
		assert( *d->premain > 0 );
		if ( cobsCDecode( dctx ) > 0 ) {
			rv = 1;
		}
		*d->premain      -= dctx->dstIndex;
		dctx->dst        += dctx->dstIndex;
		dctx->dstIndex    = 0;
	}
	return 0;
}

int
decodeFlush(const uint8_t *buf, size_t bufsz, void *closure)
{
DecoderFlusher *d = static_cast<DecoderFlusher*>(closure);
	if ( d->enc ) {
		for ( auto k = 0; k < bufsz; ++k  ) {
			d->enc->push_back( buf[k] );
		}
	}
	d->dctx->src      = buf;
	d->dctx->srcSize  = bufsz;
	d->dctx->srcIndex = 0;

	return decodeSeg( d );
}

void
vecCodecTest(const V &src, size_t encWin, size_t bufsz, size_t decWin, const V *eexp)
{
	V dst;
	V buf;
	V enc;
	dst.resize(src.size());
	buf.resize(bufsz);

	CobsCEncoderCtx ectx;
	CobsCDecoderCtx dctx;
	cobsCEncodeInit(&ectx);
	cobsCDecodeInit(&dctx);

	ectx.src     = &src[0];
	ectx.srcSize = encWin;
	ectx.dst     = &buf[0];
	ectx.dstSize = bufsz;

	dctx.src     = ectx.dst;
	dctx.srcSize = ectx.dstSize;
	dctx.dst     = &dst[0];
	dctx.dstSize = decWin;

	size_t eremain = src.size();
	size_t dremain = dst.size();
	bool   edone;
	DecoderFlusher flushData(&dctx, &dremain, &enc);
	while ( eremain > 0 ) {
		cobsCEncodeAddToFrame( &ectx, ectx.src, ectx.srcSize, COBSC_ENCODE_NO_WRAP, decodeFlush, &flushData );
		ectx.src += ectx.srcSize;
		eremain  -= ectx.srcSize;
		if ( eremain < ectx.srcSize ) {
			ectx.srcSize = eremain;
		}
	}

	cobsCEncodeAddToFrame( &ectx, nullptr, 0, COBSC_ENCODE_WRAP, decodeFlush, &flushData );

	if ( eexp ) {

//		for ( auto k = 0; k < ectx.dstIndex; ++k  ) {
//			enc.push_back( ectx.dst[k] );
//		}
		printf("Total encoded length %zd, expected %zd\n", enc.size(), eexp->size());
		assert( enc.size() == eexp->size() );
		for ( int k = 0; k < enc.size(); ++k ) {
			assert(enc[k] == (*eexp)[k]);
		}
	}


	//decodeFlush( ectx.dst, ectx.dstIndex,  &flushData );

	assert( dremain == 0 );
all_done:
	for ( int i = 0; i < src.size(); ++i ) {
		assert(dst[i] == src[i]);
	}
}

struct FillerData {
	V      *v;
	size_t idx {0};
	FillerData(V *v) : v(v) {}
};

int
filler(uint8_t *data, size_t size, void *closure)
{
	FillerData *d = static_cast<FillerData*>(closure);
	size_t rem = d->v->size() - d->idx;
	if ( rem > 0 ) {
		size_t s = (*d->v)[d->idx];
		if ( s == 0 ) {
			s = 33;
		}
		if ( s > size ) {
			s = size;
		}
		if ( s > rem ) {
			s = rem;
		}
		memcpy(data, &(*d->v)[d->idx], s);
		d->idx += s;
		return s;
	}
	return 0;
}

int
main(int argc, char **argv)
{
	V src;
	V dst;
	V buf;
	V enc;

	src.resize(1000);
	dst.resize(1000);
	for (auto it = src.begin(); it != src.end(); ++it) {
		*it = (uint8_t)lrand48();
	}
	buf.resize(300);
	CobsCEncoderCtx ectx;
	CobsCDecoderCtx dctx;
	cobsCEncodeInit(&ectx);
	cobsCDecodeInit(&dctx);
	ectx.src     = &src[0];
	ectx.srcSize = src.size();
	ectx.dst     = &buf[0];
	ectx.dstSize = buf.size();

	dctx.src     = &buf[0];
	dctx.dst     = &dst[0];

	bool done;
	do {
		done = cobsCEncode( &ectx );
		for ( auto i = 0; i < ectx.dstIndex; ++i ) {
			enc.push_back(buf[i]);
		}
		dctx.srcSize = ectx.dstIndex;
		dctx.dstSize = dst.size() - (dctx.dst - &dst[0]);
		cobsCDecode(&dctx);
		assert( done || dctx.srcIndex == dctx.srcSize );

		dctx.dst    += dctx.dstIndex;
		if ( ! done ) {
			cobsCEncodeContinue( &ectx );
			cobsCDecodeContinue( &dctx );
		}
	} while ( ! done );
	int e = src.size();
	for ( int i = 0; i < e; ++i ) {
		printf("0x%04x 0x%02x - 0x%02x - 0x%02x\n", i, src[i], dst[i], enc[i]);
		assert( src[i] == dst[i] );
		if ( src[i] != dst[i] ) {
			printf("Mismatch @ %d\n", i);
			if ( e == src.size() ) {
				e = i + 5;
			}
		}
	}

	enc.push_back(COBSC_EOF);
	vecCodecTest(src, 100, 300, 100, &enc);

	memset(&dst[0],0x33,dst.size());
	cobsCDecodeInit( &dctx );
	dctx.srcIndex = dctx.srcSize;
	FillerData fd(&enc);
	int decStatus = cobsCDecodeFromFrame(&dctx, &dst[0], dst.size(), filler, &fd);
	for (auto i=0; i < dst.size(); ++i) {
		assert( dst[i] == src[i] );
	}
	assert( decStatus > 0 );
	assert( dctx.dstIndex == dctx.dstSize );
	assert( dctx.dstIndex == dst.size()   );

	printf("Test Passed\n");
	return 0;
}


#include <deque>
#include <queue>
#include <memory>
#include <array>
#include <mutex>
#include <condition_variable>
#include <stdexcept>
#include <cstdio>
#include <cstdlib>
#include <chrono>
#include <thread>

// Simple reliable full-duplex link
//
// a) packet integrity is assumed to be checked by lower layer (CRC mismatch should result
//    in the lower layer to discard a packet).
// b) Packets are tagged with sequence numbers ('REQ'); they report to the peer by
//    acknowledging ('ACK') the received REQ number.
// c) The sender may send a limited
//       - number of outstanding packets (i.e., not-yet acked packets)
//       - amount of unacked data
// d) If the sender does not receive an ACK for an outstanding REQ then
//    *all* outstanding REQs are retransmitted in their original order.
//   I.e., the receiver is supposed to accept packets strictly in-order.
//   It does not have to handle 'holes' in the sequence and may discard
//   any out-of-sequence packets.
// e) The receiver may 'coalesce' acknowledgements; i.e., it only has
//    to ACK the latest in-sequence REQ it received.
//    When the sender receives an ACK it may remove all cached REQs from
//    the retransmission buffer up to ACK.
// f) Usually, the receiver returns ACK to the sender combined with it's own
//    payload data (associated with it's side's REQ number). This enables
//    full-duplex communication.
//    However, there are certain situations when the receiver has to
//    respond with and ACK even if it does not have any payload data ready
//    to send:
//      - when a new REQ arrives and is accepted then it should immedately
//        be ACKed.
//      - when an out-of-sequence REQ arrives (e.g., retransmission due
//        to timeout on the sender side but which had already been received
//        (e.g., lost or late-arriving ACK on the sender side) then
//        the receiver should immediately respond and ACK the latest REQ
//        received in sequence.
//    In these cases the receiver sends an empty 'ACKONLY' packet which
//    contains no payload data. ACKONLY packets are *not* scheduled for
//    retransmission (if this ACKONLY packet is lost then the sender will
//    eventually retransmit and trigger a new ACKONLY response).

namespace simple_link {

enum class MsgType { DATA, ACKONLY };

struct Header {
	uint8_t req;
	uint8_t ack;
	MsgType typ;
};

struct Msg : Header {
	int pld;
	int idx;
};

using MsgPtr = std::shared_ptr<Msg>;

class Channel {
public:
	virtual void post(MsgPtr) = 0;
	virtual MsgPtr getMsg()   = 0;
	virtual ~Channel()        = default;
};

using ChannelPtr = std::shared_ptr<Channel>;
using Timeout    = std::chrono::time_point<std::chrono::steady_clock>;

class Link : public std::enable_shared_from_this<Link> {
public:
	static constexpr const size_t                 LDDATWINSZ = 6;
private:
	static constexpr const size_t                 DATWINSZ   = (1<<LDDATWINSZ);
	static constexpr const uint8_t                SEQWINSZ   = 4;
	std::mutex                                    mtx_;
	std::condition_variable                       rexAdj_;
	std::condition_variable                       txRdy_;
	std::condition_variable                       txSpc_;
	std::condition_variable                       rxDat_;
	uint8_t                                       txReq_ { 0 };
	uint8_t                                       txAck_ { 0 };
	uint8_t                                       rxReq_ { 0 };
	uint8_t                                       rxAck_ { 0 };
	bool                                          rexActive_ { false };
	std::deque<std::pair<MsgPtr, Timeout>>        rex_;
	std::deque<MsgPtr>                            txq_;
	std::deque<MsgPtr>                            rxq_;
	ChannelPtr                                    chnl_;
	size_t                                        unackedData_ {0};

	static constexpr const std::chrono::duration REX_TIMEOUT = std::chrono::milliseconds(100);
	static constexpr const std::chrono::duration ACK_TIMEOUT = std::chrono::milliseconds(500);

	static constexpr size_t TX_Q_SIZE = 2;
public:
	Link(ChannelPtr chnl) : chnl_(chnl) {}

	virtual MsgPtr msgAlloc() {
		MsgPtr m = std::make_shared<Msg>();
		m->typ = MsgType::DATA;
		return m;
	}

	virtual MsgPtr pop() {
		std::unique_lock<std::mutex> l(mtx_);
		while ( rxq_.empty() ) {
			rxDat_.wait(l);
		}
		MsgPtr m = rxq_.front();
		rxq_.pop_front();
		return m;
	}

	virtual void rxRun() {
		while ( 1 ) {
			bool wakeRex      = false;
			bool wakeTx       = false;
			bool wakeConsumer = false;
			MsgPtr   m   = chnl_->getMsg();
			std::unique_lock<std::mutex> l(mtx_);
			// ack processing
			if ( static_cast<uint8_t>(m->ack - txAck_) <= static_cast<uint8_t>(txReq_ - txAck_) ) {
				// OK (normal case); ack is in the retransmission queue
				//
				// if window was full wake transmitter since we're going to make space
				wakeTx  = (static_cast<uint8_t>(txReq_ - txAck_) == SEQWINSZ);
				// remove anything up to 'm->ack' from the retransmission queue
				while ( ! rex_.empty() && static_cast<int8_t>(m->ack - rex_.front().first->req) >= 0 ) {
					// if the retransmission queue was changed; wake the REX thread
					wakeRex       = true;
					// if we use the 'unackedData' window we must wake the tx to recheck if there is space for
					// the next message
					wakeTx        = true;
					unackedData_ -= rex_.front().first->pld;
					printf("RX removed REQ %u ACK %u from rex q; unackedData %zu\n", rex_.front().first->req, rex_.front().first->ack, unackedData_);
					rex_.pop_front();
				}
				txAck_ = m->ack;
			} else {
				// a redundant ACK for which we already have removed the retransmission; ignore
				printf("RX Out of order ACK ?? %u, txReq %u, txAck %u\n", m->ack, txReq_, txAck_);
			}

			// req processing
			//
			if ( m->typ == MsgType::ACKONLY ) {
				// Ignore req number of ACKONLY message
				printf("RX ACK MSG r %u a %u; DROP\n", m->req, m->ack);
			} else {
				if ( m->req == static_cast<uint8_t>(rxReq_ + 1) ) {
					// New request, received in sequence
					// immediate ACK if necessary
					wakeConsumer = rxq_.empty();
					rxq_.push_back(m);
					++rxReq_;
					wakeTx       = true;
					printf("RX ACCEPT MSG r %u a %u\n", m->req, m->ack);
				} else {
					// they haven't seen the ack to this? force
					// retransmission of ack immediatelyl
					rxAck_ = rxReq_ - 1;
					wakeTx = true;
					printf("RX Redundant REQ %u ACK %u; DROP\n", m->req, m->ack);
				}
			}
			l.unlock();
			if ( wakeRex ) {
				rexAdj_.notify_one();
			}
			if ( wakeTx ) {
				txRdy_.notify_one();
			}
			if ( wakeConsumer ) {
				rxDat_.notify_one();
			}
		}
	}

	virtual void rexRun() {
		std::queue<MsgPtr> q;
		while ( 1 ) {
			MsgPtr m;
			{
				std::unique_lock<std::mutex> l(mtx_);
				while ( 1 ) {
					if ( rex_.empty() ) {
						rexAdj_.wait(l);
					} else {
						if ( std::cv_status::timeout == rexAdj_.wait_until(l, rex_.front().second) ) {
							// work to do!
							break;
						}
					}
				}
				// can only get here if the req_ queue is not empty!

				// stop the TX thread from sending and adding to the rex_ queue
				rexActive_     = true;
				uint8_t rexReq = rex_.front().first->req; // first REQ to retransmit
				uint8_t rexLst = rex_.back().first->req;  // last REQ to retransmit
				--rexReq; // re-decrement
				do {
					++rexReq;
					// check if rexReq is still in the retransmission queue; because we unlock
					// while transmission is under way the RX could receive ACKs and modify the queue
					for ( auto it = rex_.begin(); it != rex_.end(); ++it ) {
						if (it->first->req == rexReq ) {
							MsgPtr m = it->first;
							// update the ACK field; we may have seen more REQs since
							// sending the original
							m->ack = (rxAck_ = rxReq_);
							printf("REX REQ %u, ACK %u\n", m->req, m->ack);
							l.unlock();
							chnl_->post(m);
							l.lock();
							// q may have changed;
							for ( it = rex_.begin(); it != rex_.end(); ++it ) {
								if ( it->first->req == rexReq ) {
									// still there; adjust the timeout
									it->second = Timeout::clock::now() + REX_TIMEOUT;
									printf("REX readjusted timeout REQ %u, ACK %u\n", it->first->req, it->first->ack);
									break;
								}
							}
							break;
						}
					}
				} while ( rexReq != rexLst );
				rexActive_ = false;
			}
			txRdy_.notify_one(); // in case they waited for rexActive_ to become false
		}
	}

	virtual void send(MsgPtr m)
	{
		if ( m ) {
			bool notifyTx;
			{
			std::unique_lock<std::mutex> l(mtx_);
			while ( txq_.size() >= TX_Q_SIZE ) {
				txSpc_.wait(l);
			}
			notifyTx = txq_.empty();
			txq_.push_back(m);
			}
			if ( notifyTx ) {
				txRdy_.notify_one();
			}
		}
	}

	virtual void txRun() {
		while ( 1 ) {
			std::unique_lock<std::mutex> l(mtx_);
			bool canSend;
			// wait until there is
			//  either
			//    window space AND data in the txq AND retransmissions are not currently being done
			//  OR
			//    ACK needs to be sent
			//
			// Note: it doesn't make sense to send new frames while retransmissions are going on; they would
			//       arrive out of sequence and thus just consume bandwidth!
			while ( ! (canSend = (((txReq_ - txAck_) < SEQWINSZ) && ! txq_.empty() && ! rexActive_ && txq_.front()->pld + unackedData_ <= DATWINSZ)) && (rxReq_ == rxAck_) ) {
#define ACK_TIMEOUT_FOREVER
#ifdef ACK_TIMEOUT_FOREVER
				txRdy_.wait(l);
#else
				if ( std::cv_status::timeout == txRdy_.wait_for(l, ACK_TIMEOUT ) ) {
					printf("Tx run timeout\n");
					break; // send empty ACK
				}
#endif
			}
			printf("TX q empty %u, rxReq_ %u, rxAck_ %u\n", txq_.empty(), rxReq_, rxAck_);
			bool noRex   = false;
			MsgPtr m;
			if ( ! canSend ) {
				m      = msgAlloc();
				m->typ = MsgType::ACKONLY;
				// pure ACK messages are not retransmitted
				noRex  = true;
			} else {
				m      = txq_.front();
				txq_.pop_front();
				// step tx sequency number
				++txReq_;
				unackedData_ += m->pld;
			}
			m->req = txReq_;
			m->ack = (rxAck_ = rxReq_); // update rxAck_
			bool wakeRex = false;
			if ( ! noRex ) {
				// schedule retransmission
				Timeout timeout = Timeout::clock::now() + REX_TIMEOUT;
				wakeRex         = rex_.empty();
				rex_.push_back({m,timeout});
			}
			l.unlock();
			chnl_->post(m);
			if ( wakeRex ) {
				rexAdj_.notify_one();
			}
			if ( ! noRex ) {
				txSpc_.notify_one();
			}
		}
	}
};

} // namespace simple_link

template <typename T>
struct SyncQ {
	std::deque<T> q_;
	std::condition_variable         txRdy_;
	std::condition_variable         rxRdy_;
	std::mutex                      mtx_;
	size_t                          qsz_;

	SyncQ(size_t qsz) : qsz_(qsz) {}

	void push(T el) {
		bool notifyRx;
		{
			std::unique_lock<std::mutex> l(mtx_);
			while ( q_.size() >= qsz_ ) {
				txRdy_.wait(l);
			}
			notifyRx = q_.empty();
			q_.push_back(el);
		}
		if ( notifyRx ) {
			rxRdy_.notify_one();
		}
	}

	T pop() {
		bool notifyTx;
		T el;
		{
			std::unique_lock<std::mutex> l(mtx_);
			while ( q_.empty() ) {
				rxRdy_.wait(l);
			}
			notifyTx = ( q_.size() >= qsz_ );
			el = q_.front();
			q_.pop_front();
		}
		if ( notifyTx ) {
			txRdy_.notify_one();
		}
		return el;
	}
};

class Rand {
	char                            rstate_[64];
	struct random_data              rnd_;
public:
	Rand(int seed) {
		rnd_.state = nullptr;
		if ( 0 == seed ) {
			seed = 1;
		}
		initstate_r( seed, rstate_, sizeof(rstate_), &rnd_ );
	}

	// 0..2**31 - 1
	int32_t
	operator()() {
		int32_t r;
		if ( random_r( &rnd_, &r ) ) {
			throw std::runtime_error("random_r failure");
		}
		return r;
	}
};

class QChannel : public simple_link::Channel {
public:
	using QPtr = std::shared_ptr<SyncQ<simple_link::MsgPtr>>;
private:
	QPtr                            txq_, rxq_;
	Rand                            rnd_;
public:
	QChannel(QPtr txq, QPtr rxq, int seed) : txq_(txq), rxq_(rxq), rnd_(seed) {
	}

	virtual void post(simple_link::MsgPtr m) override {
		int32_t r = rnd_();
		printf("random %i\n", r);
		// NOTE: lsbit is not really that random (state size 8) and led to a certain REQ always being dropped!
		if ( true && !!(r & (1<<30)) ) {
			printf("message posted random DROP REQ %u, ACK %u\n", m->req, m->ack);
			return; // drop
		}
		txq_->push(m);
		printf("message posted REQ %u, ACK %u\n", m->req, m->ack);
	}

	virtual simple_link::MsgPtr getMsg() override {
		simple_link::MsgPtr m = rxq_->pop();
		printf("message popped REQ %u, ACK %u\n", m->req, m->ack);
		return m;
	}
};

using LPtr = std::shared_ptr<simple_link::Link>;

class Checker {
	LPtr   ltx_;
	LPtr   lrx_;
	Rand   rndtx_;
	Rand   rndrx_;
	const size_t loops_;
	std::thread  rxTid_;
	std::thread  txTid_;
public:
	Checker(LPtr ltx, LPtr lrx, int seed, size_t loops)
	: ltx_(ltx), lrx_(lrx),
	  rndtx_(seed), rndrx_(seed),
	  loops_(loops) {
	}

private:
	void txRun() {
		for ( size_t i = 0; i < loops_; ++i ) {
			auto m = ltx_->msgAlloc();
			m->pld = (rndtx_() & ((1<<LPtr::element_type::LDDATWINSZ) - 1));
			m->idx = i;
			ltx_->send(m);
		}
	}

	void rxRun() {
		for ( size_t i = 0; i < loops_; ++i ) {
			auto m = lrx_->pop();
			printf("CHECK idx %i\n", m->idx);
			if ( m->pld != (rndrx_() & ((1<<LPtr::element_type::LDDATWINSZ) - 1)) ) {
				throw std::runtime_error("Test FAILED - payload mismatch");
			}
		}
		printf("Test PASSED\n");
		fflush(stdout);
	}
public:
	void spawn() {
		txTid_ = std::thread(&Checker::txRun, this);  
		rxTid_ = std::thread(&Checker::rxRun, this);
	}

	void join() {
		txTid_.join();
		rxTid_.join();
	}
};

int
main()
{
	QChannel::QPtr aq = std::make_shared<QChannel::QPtr::element_type>(2);
	QChannel::QPtr bq = std::make_shared<QChannel::QPtr::element_type>(2);
	LPtr l1 = std::make_shared<LPtr::element_type>(std::make_shared<QChannel>(aq, bq, 2));
	LPtr l2 = std::make_shared<LPtr::element_type>(std::make_shared<QChannel>(bq, aq, 5));
	std::thread rexTid1( &simple_link::Link::rexRun, l1 );
	std::thread rxTid1 ( &simple_link::Link::rxRun,  l1 );
	std::thread txTid1 ( &simple_link::Link::txRun,  l1 );

	std::thread rexTid2( &simple_link::Link::rexRun, l2 );
	std::thread rxTid2 ( &simple_link::Link::rxRun,  l2 );
	std::thread txTid2 ( &simple_link::Link::txRun,  l2 );

	Checker check1(l1, l2, 123,  100);
	Checker check2(l2, l1, 1023, 100);
	check1.spawn();
	check2.spawn();
	check1.join();
	check2.join();

	for (int i = 10; i < 13; ++i) {
		auto m = l1->msgAlloc();
		m->pld = i;
		l1->send(m);
	}
	fflush(stdout);

	std::this_thread::sleep_for(std::chrono::seconds(2));

	for ( auto m = l2->pop(); m; m=l2->pop() ) {
		printf("Got SEQ %i\n", m->pld);
		fflush(stdout);
	}

	rexTid1.join();
	rxTid1.join();
	txTid1.join();
	rexTid2.join();
	rxTid2.join();
	txTid2.join();
}

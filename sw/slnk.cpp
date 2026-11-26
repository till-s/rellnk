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

#define DBGPRINTF(args...) do {} while (0)

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

enum class MsgType { DATA, ACKONLY, SYN };

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
	// recvMsg to return nullptr when the channel is shut down;
	// this can be used to terminate RX threads
	virtual MsgPtr rcvMsg()   = 0;
	virtual ~Channel()        = default;
};

using ChannelPtr = std::shared_ptr<Channel>;
using Timeout    = std::chrono::time_point<std::chrono::steady_clock>;

class Link : public std::enable_shared_from_this<Link> {
public:
	static constexpr const int                    LDDATWINSZ = 6;
private:
	static constexpr const size_t                 DATWINSZ   = (LDDATWINSZ >= 0 ? (1<<LDDATWINSZ) : 0);
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
	bool                                          synActive_ { false };
	bool                                          running_ { true };
	std::deque<std::pair<MsgPtr, Timeout>>        rex_;
	std::deque<MsgPtr>                            txq_;
	std::deque<MsgPtr>                            rxq_;
	ChannelPtr                                    chnl_;
	size_t                                        unackedData_ {0};

	static constexpr const std::chrono::duration REX_TIMEOUT = std::chrono::milliseconds(100);
	static constexpr const std::chrono::duration ACK_TIMEOUT = std::chrono::milliseconds(500);

	static constexpr size_t TX_Q_SIZE = 2;

protected:
	void syncUnlocked(bool purgeTx, bool purgeRx) {
		txReq_ = 0; // RW by RX and TX
		txAck_ = 0; // RW by RX, RO by TX
		rxReq_ = 0; // RW by RX, RO by TX, RO by REX
		rxAck_ = 0; // WO by RX, RW by TX, RO by REX
		// Do NOT reset 'rexActive_': if the REX thread just has done a retransmission
		// it will lock again and inspect the queue. If we reset rexActive_ here we
		// would create a race: the TX thread runs first it could add new packets to the
		// rex queue which would then be picked up by the REX thread.
		//
		// Just clearing the rex_ queue is enough. In the scenario described above the
		// REX thread would find the queue empty and proceed to reset rexActive_.
		// rexActive_ = false;
		while ( ! rex_.empty() ) {
			rex_.pop_front();
		}

		if ( purgeTx ) {
			while ( ! txq_.empty() ) {
				txq_.pop_front();
			}
			txSpc_.notify_one();
		}
		if ( purgeRx ) {
			while ( ! rxq_.empty() ) {
				rxq_.pop_front();
			}
		}
		// hold off transmitter
		synActive_   = true;
		unackedData_ = 0;
	}
public:
	Link(ChannelPtr chnl) : chnl_(chnl) {}

	virtual void shutdown() {
		{
		std::unique_lock<std::mutex> l(mtx_);
		running_ = false;
		}
		rexAdj_.notify_one();
		txSpc_.notify_all();
		txRdy_.notify_all();
		rxDat_.notify_all();
	}

	// prepare for new threads; link must  have been shutdown first
	virtual void reset() {
		std::unique_lock<std::mutex> l(mtx_);
		if ( running_ ) {
			l.unlock();
			fprintf(stderr, "WARNING: Link::reset() ignored - link still running\n");
			return;
		}
		syncUnlocked(true, true);
		running_ = true;
		// new threads may be spawned after this
	}

	virtual MsgPtr msgAlloc() {
		MsgPtr m = std::make_shared<Msg>();
		m->typ = MsgType::DATA;
		return m;
	}

	// returns nullptr if the link has been shut down
	virtual MsgPtr pop() {
		std::unique_lock<std::mutex> l(mtx_);
		while ( running_ && rxq_.empty() ) {
			rxDat_.wait(l);
		}
		if ( ! running_ ) {
			return MsgPtr();
		}
		MsgPtr m = rxq_.front();
		rxq_.pop_front();
		return m;
	}

	// request SYNC with peer (start a new connection).
	// Note that concurrent attempts to sync by both peers
	// may lead to undefined behavior. Usually one station
	// is the 'master' and issues sync() whereas the
	// other station is passive and only synchronizes
	// when requested by the master.
	virtual void sync() {
		std::unique_lock<std::mutex> l(mtx_);
		syncUnlocked(false, true);
		// stop TX
		synActive_ = true;
		while ( synActive_ ) {
			// after unlocking
			//  - no TX may happen (synActive_ block TX thread)
			//  - no REX may happen ( rex_ queue is empty)
			//  - RX knows to toss packets until SYN is received
			l.unlock();
			sendSyn();
			l.lock();
			// use txRdy condvar; tx thread is also waiting for synActive_ resetting
			txRdy_.wait_until(l, Timeout::clock::now() + REX_TIMEOUT);
		}
	}

	virtual void sendSyn() {
		MsgPtr m = msgAlloc();
		m->typ = MsgType::SYN;
		m->req = txReq_;
		m->ack = rxAck_;
		chnl_->post(m);
	}

	virtual void rxRun() {
		// hold a reference of the shared pointer while running
		// if this method is overridden the subclass may have
		// to acquire another reference to prevent destruction
		auto ref = shared_from_this();

		MsgPtr m;
		while ( (m = chnl_->rcvMsg()) ) {
			bool wakeRex      = false;
			bool wakeTx       = false;
			bool wakeConsumer = false;
			std::unique_lock<std::mutex> l(mtx_);
			// syn processing
			if ( MsgType::SYN == m->typ ) {
				if ( synActive_ ) {
					// we issued a SYN and received a reply -- all done
				} else {
					// we received a SYN request; reset and send reply
					syncUnlocked(false, false);
					// synActive_ is now asserted; TX thread cannot send; REX queue is empty
					l.unlock();
					sendSyn();
					l.lock();
				}
				synActive_ = false;
				l.unlock();
				txRdy_.notify_all(); // possibly, TX thread and syncRequest are waiting
				continue;
			}
			if ( synActive_ ) {
				// waiting for SYN reply; ditch everything until we do receive it
				continue;
			}
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
					if ( DATWINSZ ) {
						// if we use the 'unackedData' window we must wake the tx to recheck if there is space for
						// the next message
						wakeTx        = true;
						unackedData_ -= rex_.front().first->pld;
					}
					DBGPRINTF("RX removed REQ %u ACK %u from rex q; unackedData %zu\n", rex_.front().first->req, rex_.front().first->ack, unackedData_);
					rex_.pop_front();
				}
				txAck_ = m->ack;
			} else {
				// a redundant ACK for which we already have removed the retransmission; ignore
				DBGPRINTF("RX Out of order ACK ?? %u, txReq %u, txAck %u\n", m->ack, txReq_, txAck_);
			}

			// req processing
			//
			if ( MsgType::ACKONLY == m->typ ) {
				// Ignore req number of ACKONLY message
				DBGPRINTF("RX ACK MSG r %u a %u; DROP\n", m->req, m->ack);
			} else {
				if ( m->req == static_cast<uint8_t>(rxReq_ + 1) ) {
					// New request, received in sequence
					// immediate ACK if necessary
					wakeConsumer = rxq_.empty();
					rxq_.push_back(m);
					++rxReq_;
					wakeTx       = true;
					DBGPRINTF("RX ACCEPT MSG r %u a %u\n", m->req, m->ack);
				} else {
					// they haven't seen the ack to this? force
					// retransmission of ack immediatelyl
					//
					rxAck_ = rxReq_ - 1;
					wakeTx = true;
					DBGPRINTF("RX Redundant REQ %u ACK %u; DROP\n", m->req, m->ack);
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
		// hold a reference of the shared pointer while running
		// if this method is overridden the subclass may have
		// to acquire another reference to prevent destruction
		auto ref = shared_from_this();

		std::queue<MsgPtr> q;
		while ( 1 ) {
			MsgPtr m;
			{
				std::unique_lock<std::mutex> l(mtx_);
				while ( running_ && (rex_.empty() || (Timeout::clock::now() < rex_.front().second)) ) {
					if ( rex_.empty() ) {
						rexAdj_.wait(l);
					} else {
						rexAdj_.wait_until(l, rex_.front().second);
					}
				}
				if ( ! running_ ) {
					break;
				}
				// can only get here if the req_ queue is not empty and the
				// front element's timeout has expired!

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
							DBGPRINTF("REX REQ %u, ACK %u\n", m->req, m->ack);
							l.unlock();
							chnl_->post(m);
							l.lock();
							// q may have changed;
							for ( it = rex_.begin(); it != rex_.end(); ++it ) {
								if ( it->first->req == rexReq ) {
									// still there; adjust the timeout
									it->second = Timeout::clock::now() + REX_TIMEOUT;
									DBGPRINTF("REX readjusted timeout REQ %u, ACK %u\n", it->first->req, it->first->ack);
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

	virtual void send(MsgPtr m) {
		if ( m ) {
			bool notifyTx;
			{
			std::unique_lock<std::mutex> l(mtx_);
			while ( running_ && (txq_.size() >= TX_Q_SIZE) ) {
				txSpc_.wait(l);
			}
			if ( ! running_ ) {
				// silently dump
				return;
			}
			notifyTx = txq_.empty();
			txq_.push_back(m);
			}
			if ( notifyTx ) {
				txRdy_.notify_one();
			}
		}
	}

	//         M                           S
	//           P1  SYN P2              P1 SYN P2      
	//           rxpre                   P3 SYN
	//
	//
	//       M tx     P1    SYN    P2
	//         rx                       SYN     
	//       S tx               P3  SYN P4        
	//         rx        P1     SYN     P2      
	//           -----------------------------------------------------------> t

	virtual void txRun() {
		// hold a reference of the shared pointer while running
		// if this method is overridden the subclass may have
		// to acquire another reference to prevent destruction
		auto ref = shared_from_this();

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
			while (1) {
				if ( ! running_ ) {
					goto bail;
				}
				// sending not blocked
				canSend = ! rexActive_ && ! synActive_;
				// AND TX window open
				canSend = canSend && ((txReq_ - txAck_) < SEQWINSZ);
				// AND there is something to send
				canSend = canSend && ! txq_.empty();
				if ( DATWINSZ ) {
					// AND txdata fits (if DATWINSZ is enabled)
					canSend = canSend && (txq_.front()->pld + unackedData_ <= DATWINSZ);
				}
				if ( canSend || (rxReq_ != rxAck_) ) {
					break;
				}
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
			//printf("TX q empty %u, rxReq_ %u, rxAck_ %u\n", txq_.empty(), rxReq_, rxAck_);
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
				if ( DATWINSZ ) {
					unackedData_ += m->pld;
				}
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
	bail:
		// avoid 'label at end of compound statement' warnings
		do {} while (0);
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
	bool                            running_;

	SyncQ(size_t qsz) : qsz_(qsz), running_(true) {}

	void shutdown() {
		{
		std::unique_lock<std::mutex> l(mtx_);
		running_ = false;
		// purge queue; this unblocks 'push' waiting for the queue to drain
		while ( ! q_.empty() ) {
			q_.pop_front();
		}
		}
		txRdy_.notify_all();
		rxRdy_.notify_all();

	}

	void push(T el) {
		bool notifyRx;
		{
			std::unique_lock<std::mutex> l(mtx_);
			while ( q_.size() >= qsz_ ) {
				txRdy_.wait(l);
			}
			if ( running_ ) {
				notifyRx = q_.empty();
				q_.push_back(el);
			}
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
			while ( q_.empty() && running_ ) {
				rxRdy_.wait(l);
			}
			if ( ! running_ ) {
				return el;
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
		DBGPRINTF("random %i\n", r);
		// NOTE: lsbit is not really that random (state size 8) and led to a certain REQ always being dropped!
		if ( true && !!(r & (1<<30)) ) {
			DBGPRINTF("message posted random DROP REQ %u, ACK %u\n", m->req, m->ack);
			return; // drop
		}
		txq_->push(m);
		DBGPRINTF("message posted REQ %u, ACK %u\n", m->req, m->ack);
	}

	virtual simple_link::MsgPtr rcvMsg() override {
		simple_link::MsgPtr m = rxq_->pop();
		DBGPRINTF("message popped REQ %u, ACK %u\n", m->req, m->ack);
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

	Checker check1(l1, l2, 123,  10);
	Checker check2(l2, l1, 1023, 10);
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

	for (int i = 10; i < 13; ++i) {
		auto m = l2->pop();
		if ( m->pld != i ) {
			throw std::runtime_error("Test FAILED - payload mismatch (1)");
		}
		printf("Got SEQ %i\n", m->pld);
		fflush(stdout);
	}

	aq->shutdown();
	bq->shutdown();
	l1->shutdown();
	l2->shutdown();

	rexTid1.join();
	rxTid1.join();
	txTid1.join();
	rexTid2.join();
	rxTid2.join();
	txTid2.join();
}

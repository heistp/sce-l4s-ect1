# SCE-L4S ECT(1) Test Results

Evidence in support of using ECT(1) as an output signal, rather than
an input classifier, for high fidelity congestion control

Pete Heist  
Jonathan Morton  

## Table of Contents

1. [Introduction](#introduction)
2. [Key Findings](#key-findings)
3. [Elaboration on Key Findings](#elaboration-on-key-findings)
5. [Choosing Input vs Output](#choosing-input-vs-output)
5. [Full Results](#full-results)
   1. [Scenario 1: One Flow](#scenario-1-one-flow)
   2. [Scenario 2: Two Flow Competition](#scenario-2-two-flow-competition)
   3. [Scenario 3: Bottleneck Shift](#scenario-3-bottleneck-shift)
   4. [Scenario 4: Capacity Reduction](#scenario-4-capacity-reduction)
   5. [Scenario 5: WiFi Burstiness](#scenario-5-wifi-burstiness)
   6. [Scenario 6: Jitter](#scenario-6-jitter)
6. [Appendix](#appendix)
   1. [Background](#background)
   2. [Typical Internet Jitter](#typical-internet-jitter)
   3. [Test Setup](#test-setup)

## Introduction

The Transport Area Working Group
([TSVWG](https://datatracker.ietf.org/group/tsvwg/about/)) is undergoing a
process to decide if to reclassify the current ECT(1) codepoint for use in
high-fidelity congestion control. Two competing proposals define different,
incompatible uses for ECT(1) in order to achieve similar goals, but in a
very different way:

1. [SCE](https://tools.ietf.org/html/draft-morton-tsvwg-sce-01) uses ECT(1) as
   an output from the network, a proportional congestion signal that indicates a
   lesser degree of congestion than CE. With SCE, ECT(1) is the high fidelity
   congestion control signal.  CE retains its original RFC-3168 semantics.

2. [L4S](https://riteproject.eu/dctth/) uses ECT(1) as an input to the network,
   a classifier indicating alternate semantics for the CE codepoint. With L4S,
   CE is the high fidelity congestion control signal, and ECT(1) selects between
   the prior (RFC-3168) and new meaning of CE.

**Note that the meaning of SCE is essentially the same as L4S's alternate
semantics for CE.** However, because ECT(1) is the last usable codepoint left in
the IP header, only one of the two proposals, or neither, may be chosen. This
report provides evidence in support of SCE and using ECT(1) as an output signal,
rather than an input classifier, for high-fidelity congestion control.

Readers wishing for a quick background in high-fidelity congestion control
may wish to read the [Background](#background) section, while those already
familiar with the topic can proceed to the [Key Findings](#key-findings).

## Key Findings

1. In the L4S reference implementation, RFC 3168 bottleneck detection is
   unreliable in at least the following ways:
   *  *False negatives* (undetected RFC 3168 bottlenecks) occur with tightened
      AQM settings for Codel, RED and PIE, resulting in the starvation
      of competing traffic (in [Scenario 2](#scenario-2-two-flow-competition),
      see results for the aforementioned qdiscs).
   *  *False positives* (L4S bottlenecks incorrectly identified as RFC 3168)
      occur in the presence of about 2ms or more of jitter, resulting in
      under-utilization (see the L4S results in [Scenario
      6](#scenario-6-jitter)). Further false positives also occur at low
      bandwidths, with the same effect (see [Scenario 1](#scenario-1-one-flow)
      at 5Mbit, with 80ms or 160ms RTT).
   *  *Insensitivity* to the delay-variation signal occurs when packet loss is
      experienced.  If the detection is currently for L4S, it will remain so,
      and likewise for RFC 3168.  This interacts adversely with dropping AQMs.
2. In the L4S reference implementation, packet loss is apparently not treated as
   a congestion signal, unless the detection algorithm has placed it in
   the RFC 3168 compatible mode.  This does not adhere to the principle of
   effective congestion control (for one example, in
   [Scenario 2](#scenario-2-two-flow), see the pfifo results for L4S).
3. *Ultra-low delay*, defined here as queueing delay <= ~1ms, is **not**
   achievable for the typically bursty traffic on the open Internet without
   significant reductions in utilization, and should therefore not be a key
   selection criteria between the two proposals when it comes to the ECT(1)
   codepoint decision (in [Scenario 5](#scenario-5-wifi-burstiness), see
   Prague utilization in L4S results, compared to twin_codel_af utilization with
   Codel's burst-tolerant SCE marking behavior, in the SCE results).
4. Ultra-low delay **is** achievable in the SCE architecture on appropriate
   paths, currently by using DSCP as a classifier to select tightened AQM
   settings (in [Scenario 1](#scenario-1-one-flow), see 50Mbit and 250Mbit cases
   at 20ms RTT).

## Elaboration on Key Findings

Whenever you rely on a heuristic, rather than an explicit signal, you need to establish:
- which cases may result in false-positive detections (defined here as detecting a path as a classic AQM when in fact it is providing L4S signalling),
- which may result in false-negative detections (defined here as failing to recognise a classic AQM as such), and
- what circumstances may result in an unintentional desensitisation of the heuristic.

You also need to determine how severe the consequences of these failures are,
which in this case means checking the degree of unfairness to competing traffic that results, and the impact on the performance
of the L4S flow itself.  This is what we set out to look for.

### Utopia

First, to give some credit, the "classic AQM detection heuristic" does appear to work in some circumstances, as we can see in the following plot:

![When everything goes well](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/l4s-s2-twoflow-ns-cubic-vs-prague-codel1q-80ms_tcp_delivery_with_rtt.svg)  
*Figure 1*  

When faced with a single-queue Codel or PIE AQM at default parameters, TCP Prague appears to successfully switch into its fallback mode 
and compete with reasonable fairness.  Under good network conditions, it also correctly detects an L4S queue at the 
bottleneck.  It even successfully copes with the tricky case of the bottleneck being changed between DualQ-PI2 and a PIE 
instance with ECN disabled, though it takes several sawtooth cycles to switch back into L4S mode after DualQ-PI2 is restored 
to the path.  We suspect this represents the expected behaviour of the heuristic, from its authors' point of view.

However, we didn't have to expand our search very far to find cases that the heuristic did not cope well with, and some of 
which even appeared to break TCP Prague's congestion control entirely.  That is where our concern lies.

### False Negatives

![Hunting for the wrong answer](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/l4s-s2-twoflow-ns-cubic-vs-prague-red_150000_-80ms_tcp_delivery_with_rtt.svg)
*Figure 2*  

**False-negative detections are the most serious,** when it comes to maintaining "friendly coexistence" with conventional 
traffic.  We found them in three main areas:
 * Using RED with a limit of 150000, in which the heuristic can oscillate between detection states (see *Figure 2*),
 * Codel and PIE instances tuned for shorter path lengths than default, in which the delay-variance signal that the 
heuristic relies upon is attenuated (see *Figure 3*),
 * Queues which signal congestion with packet-drops instead of ECN marks, including dumb drop-tail FIFOs (both deep and 
shallow) which represent the majority of queues in today's Internet, and PIE with ECN support disabled as it is in 
DOCSIS-3.1 cable modems.  We hypothesise this is due to desensitising of the heuristic in the presence of drops, combined 
with a separate and more serious fault that we'll discuss later.

![Codel 1q 20ms target](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/l4s-s2-twoflow-ns-cubic-vs-prague-codel1q_20ms_-80ms_tcp_delivery_with_rtt.svg)
*Figure 3*  

The above failure scenarios are not at all exotic, and can be encountered either
by accident, in case of a mis-configuration, or on purpose, when an AQM
is configured to prioritize low delay or low memory consumption over
utilization.  This should cast serious doubt over reliance on this 
heuristic for maintaining effective congestion control on the Internet.  By contrast, SCE flows encountering these same scenarios
behave indistinguishably from normal CUBIC or NewReno flows.

### False Positives

![Serialisation killer](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s1-oneflow/l4s-s1-oneflow-ns-prague-dualpi2-5Mbit-80ms_tcp_delivery_with_rtt.svg)
*Figure 4*

**False-positive detections undermine L4S performance,** as measured by the criteria of maintaining minimum latency and 
maximum throughput on suitably fitted networks.  We found these in three main areas:
 * Low-capacity paths (see *Figure 4* above for a 5Mbps result) introduce enough latency variance via the serialisation delay of individual packets to
trigger the heuristic.  This prevents L4S from using the full capacity of these links, which is especially desirable.
 * Latency variation introduced by bursty and jittery paths, such as those including a simulated wifi segment, also trigger 
the heuristic.  This occurs even if the wifi link is never the overall bottleneck in the path, and the actual bottleneck has 
L4S support.
 * After the bottleneck shifts from a conventional AQM to an L4S one, it takes a number of seconds for the heuristic to 
notice this, usually over several AIMD sawtooth cycles.

L4S flows affected by a false-positive detection will have their throughput cut to significantly less than the true path 
capacity, especially if competing at the bottleneck with unaffected L4S flows.

### Desensitisation

![Ribbed for nobody's pleasure](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/l4s-s2-twoflow-ns-cubic-vs-prague-pfifo_1000_-80ms_tcp_delivery_with_rtt.svg)
*Figure 5*

**Desensitising** of the heuristic appears to occur in the presence of packet drops (see *Figure 5*).  We are not certain why this would have 
been designed in, although one hypothesis is that it was added to improve behaviour on the "capacity reduction" test we 
presented at an earlier TSVWG interim meeting.  During that test, we noticed that L4S previously exhibited a lot of packet 
loss, followed by a long recovery period with almost no goodput.  Now, there is still a lot of loss at the reduction stage, 
but the recovery time is eliminated.

This desensitising means that TCP Prague remains in the L4S mode when in fact the path produces conventional congestion 
control signals by packet loss instead of ECN marks.  The exponential growth of slow-start means that the first loss is 
experienced before the heuristic has switched over to the classic fallback mode, even if it occurs only after filling an 
80ms path and a 250ms queue (which are not unusual on Internet paths).  However, this would not necessarily be a problem as 
long as packet loss is always treated as a *conventional* congestion signal, and responded to with the conventional 
Multiplicative Decrease.

### Ignoring Packet Loss

Unfortunately, that brings us to the final flaw in TCP Prague's congestion control that we identified.  When in the classic 
fallback mode, TCP Prague does indeed respond to loss in essentially the correct manner.  However when in L4S mode, it 
appears to ignore loss entirely for the purposes of congestion control (see *Figure 6*).  **We repeatably observed full utilisation of the 
receive window in the face of over 90% packet loss.** A competing TCP CUBIC flow was completely starved of throughput; 
exactly the sort of behaviour that occurred during the congestion collapse events of the 1980s, which the AIMD congestion 
control algorithm was introduced to solve.

![Absolutely Comcastic](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/l4s-s2-twoflow-ns-cubic-vs-prague-pie_noecn_-160ms_tcp_delivery_with_rtt.svg)
*Figure 6*

**This is not effective congestion control.**

### Ultra Low Delay

Foremost in L4S' key goals is "Consistently ultra low latency".  A precise definition of this is difficult to find 
in their documentation, but conversations indicate that they aim to achieve **under 1ms of peak queue delay.**  We consider 
this to be an unachievable goal on the public Internet, due to the jitter and burstiness of real traffic and real Internet 
paths.  Even the receive path of a typical Ethernet NIC has about 1ms of jitter, due to interrupt latency designed in to
reduce CPU load.

Some data supporting this conclusion is [included in the appendix](#typical-internet-jitter), which shows that over even 
modest geographical distances on wired connections, the jitter on the path can be larger than the peak delay L4S
targets.  Over intercontinental distances it is larger still.  But this jitter has to be accommodated in the queue to maintain full 
throughput, which is another stated L4S goal.

To accommodate these real-world effects, the SCE reference implementation defaults to 2.5ms target delay (without the low-latency
PHB), and accepts short-term delay excursions without excessive congestion signalling.

The L4S congestion signalling strategy is much more aggressive, so that encountering this level of jitter causes a severe 
reduction in throughput - all the more so because this also triggers the classic AQM detection heuristic.

The following two plots (*Figure 7* and *Figure 8*) illustrate the effect of adding a simulated wifi link to a typical 80ms Internet path - first with 
an SCE setup, then with an L4S one.  These plots have the same axis scales.  The picture is broadly similar on a 20ms path, too.

![Wireless SCE](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s5-burstiness/sce-s5-burstiness-ns-cubic-sce-twin_codel_af-50Mbit-80ms_tcp_delivery_with_rtt.svg)
*Figure 7*
![Wireless L4S](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s5-burstiness/l4s-s5-burstiness-ns-prague-dualpi2-50Mbit-80ms_tcp_delivery_with_rtt.svg)
*Figure 8*

A larger question might be: what *should* "ultra low delay" be defined as, in an Internet context?  Perhaps we should refer 
to what queuing delay is *typically* observed today.  As an extreme outlier, this author has personally experienced over 40 seconds 
of queue delay, induced by a provisioning shaper at a major ISP.  Most good network engineers would agree that even 4 
seconds is excessive.  A "correctly sized" drop-tail FIFO might reach 400ms during peak traffic hours, when capacity is 
stretched and available bandwidth per subscriber is lower than normal - so let's take that as our reference point.

Compared to 400ms, a conventional AQM might show a 99th-percentile delay of 40ms under sustained load.  We can reasonably 
call that "low latency", as it's comparable to a single frame time of standard-definition video (at 25 fps), and well within the 
preferred jitter buffer dimensions of typical VoIP clients.  So perhaps "ultra low delay" is reasonably defined as an 
order of magnitude better than that, at 4ms; that's comparable to the frame time of a high-end gaming monitor.

Given experience with SCE's default 2.5ms target delay, we think 4ms peak delay is realistically achievable on a good, short 
Internet path with full throughput.  The Codel AQM we've chosen for SCE can already achieve that in favourable 
conditions, while still obtaining reasonable throughput and latency control when conditions are less than ideal.

There is nothing magical about the codepoint used for this signalling; both L4S and SCE should be able to achieve the same 
performance if the same algorithms are applied.  But SCE aims for an achievable goal with the robustness to permit safe 
experimentation, and this may fundamentally explain the contrast in the plots above.

## Choosing Input vs Output

SCE defines ECT(1) as an output from the network; it is set by an AQM at a
network node to request a small reduction in send rate, while the conventional
CE mark remains as a way to request a large reduction.  The network does not
know whether the traffic it passes is SCE capable or not, only whether it is ECN
capable.  Hence the network must be prepared for the additional SCE signal to be
ignored, as conventional transports will.  On the other hand, there is no
confusion at the transport layer as to what meaning a given ECN signal carries;
ECT(1) always means a small reduction, CE always means a large one.

The practical upshot is that SCE transports operating over a conventional
bottleneck will naturally exhibit normal, conventional behaviour that is
effectively indistinguishable from that of a conventional transport.  This is
obviously safe from a congestion control perspective.  This is also true if the
additional SCE signal is somehow erased.

The only real concern is with fairness between SCE and conventional flows when SCE signalling is available, but this is 
straightforward to address at the network nodes implementing SCE signalling, provided SCE and non-SCE flows can be 
distinguished from each other.  For this purpose, the traditional 5-tuple of (srcaddr, dstaddr, proto, srcport, dstport) is 
sufficient.  In IPv6, the alternative 4-tuple of (srcaddr, dstaddr, proto, flowlabel) can achieve the same result without 
needing Layer 4 visibility.

By contrast, L4S defines ECT(1) as an input to the network; it is set by a
sender to request alternative treatment by the network.  This involves both a
change in queue behaviour and a change in the AQM signalling algorithm.  These
changes are intended to match the changes at the transport level, so that the
flow competes fairly with conventional flows sharing the same bottleneck.

However, this only works if the network (in particular, whichever node happens
to be the bottleneck) understands this signal, but current networks universally
do not.  Moreover, unlike SCE, an L4S transprt has no explicit way to tell
whether the network that passed their traffic did understand the signal, and
therefore what an AQM is requesting with any given CE mark - a large reduction
or a small one.

It has been established that if an L4S transport runs through a conventional AQM
bottleneck but still expects the L4S treatment, the result is that competing
flows are starved by the far more aggressive behaviour of the L4S transport
under identical signalling.  To address this issue, the L4S developers have
recently proposed and implemented a "classic queue detection heuristic" which is
intended to cause L4S transports to revert to conventional behaviour when it is
required.

If the L4S experiment goes ahead, this heuristic will be critical to effective
congestion control on the Internet.  We therefore took the opportunity to run
some basic tests of the heuristic's accuracy, and the resulting performance of
the L4S transport under realistically typical network conditions.  We are very
concerned by what we have found.

## Full Results

In the following results, the links are named as follows:

- _plot_: the plot svg
- _cli.pcap_: the client pcap
- _srv.pcap_: the server pcap
- _teardown_: the teardown log, showing qdisc config and stats

### Scenario 1: One Flow

Bandwidth | RTT | [SCE](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s1-oneflow/) | [L4S](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s1-oneflow/)
--------- | --- | -------------------------------------------------------------------------- | --------------------------------------------------------------------------
5Mbit | 20ms | [plot](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s1-oneflow/sce-s1-oneflow-ns-cubic-sce-twin_codel_af-5Mbit-20ms_tcp_delivery_with_rtt.svg) - [cli.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s1-oneflow/batch-sce-s1-oneflow-ns-cubic-sce-twin_codel_af-5Mbit-20ms.tcpdump_cli_cli.r.pcap.xz) - [srv.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s1-oneflow/batch-sce-s1-oneflow-ns-cubic-sce-twin_codel_af-5Mbit-20ms.tcpdump_srv_srv.l.pcap.xz) - [teardown](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s1-oneflow/batch-sce-s1-oneflow-ns-cubic-sce-twin_codel_af-5Mbit-20ms.teardown.log) | [plot](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s1-oneflow/l4s-s1-oneflow-ns-prague-dualpi2-5Mbit-20ms_tcp_delivery_with_rtt.svg) - [cli.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s1-oneflow/batch-l4s-s1-oneflow-ns-prague-dualpi2-5Mbit-20ms.tcpdump_cli_cli.r.pcap.xz) - [srv.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s1-oneflow/batch-l4s-s1-oneflow-ns-prague-dualpi2-5Mbit-20ms.tcpdump_srv_srv.l.pcap.xz) - [teardown](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s1-oneflow/batch-l4s-s1-oneflow-ns-prague-dualpi2-5Mbit-20ms.teardown.log)
5Mbit | 80ms | [plot](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s1-oneflow/sce-s1-oneflow-ns-cubic-sce-twin_codel_af-5Mbit-80ms_tcp_delivery_with_rtt.svg) - [cli.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s1-oneflow/batch-sce-s1-oneflow-ns-cubic-sce-twin_codel_af-5Mbit-80ms.tcpdump_cli_cli.r.pcap.xz) - [srv.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s1-oneflow/batch-sce-s1-oneflow-ns-cubic-sce-twin_codel_af-5Mbit-80ms.tcpdump_srv_srv.l.pcap.xz) - [teardown](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s1-oneflow/batch-sce-s1-oneflow-ns-cubic-sce-twin_codel_af-5Mbit-80ms.teardown.log) | [plot](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s1-oneflow/l4s-s1-oneflow-ns-prague-dualpi2-5Mbit-80ms_tcp_delivery_with_rtt.svg) - [cli.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s1-oneflow/batch-l4s-s1-oneflow-ns-prague-dualpi2-5Mbit-80ms.tcpdump_cli_cli.r.pcap.xz) - [srv.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s1-oneflow/batch-l4s-s1-oneflow-ns-prague-dualpi2-5Mbit-80ms.tcpdump_srv_srv.l.pcap.xz) - [teardown](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s1-oneflow/batch-l4s-s1-oneflow-ns-prague-dualpi2-5Mbit-80ms.teardown.log)
5Mbit | 160ms | [plot](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s1-oneflow/sce-s1-oneflow-ns-cubic-sce-twin_codel_af-5Mbit-160ms_tcp_delivery_with_rtt.svg) - [cli.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s1-oneflow/batch-sce-s1-oneflow-ns-cubic-sce-twin_codel_af-5Mbit-160ms.tcpdump_cli_cli.r.pcap.xz) - [srv.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s1-oneflow/batch-sce-s1-oneflow-ns-cubic-sce-twin_codel_af-5Mbit-160ms.tcpdump_srv_srv.l.pcap.xz) - [teardown](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s1-oneflow/batch-sce-s1-oneflow-ns-cubic-sce-twin_codel_af-5Mbit-160ms.teardown.log) | [plot](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s1-oneflow/l4s-s1-oneflow-ns-prague-dualpi2-5Mbit-160ms_tcp_delivery_with_rtt.svg) - [cli.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s1-oneflow/batch-l4s-s1-oneflow-ns-prague-dualpi2-5Mbit-160ms.tcpdump_cli_cli.r.pcap.xz) - [srv.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s1-oneflow/batch-l4s-s1-oneflow-ns-prague-dualpi2-5Mbit-160ms.tcpdump_srv_srv.l.pcap.xz) - [teardown](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s1-oneflow/batch-l4s-s1-oneflow-ns-prague-dualpi2-5Mbit-160ms.teardown.log)
50Mbit | 20ms | [plot](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s1-oneflow/sce-s1-oneflow-ns-cubic-sce-twin_codel_af-50Mbit-20ms_tcp_delivery_with_rtt.svg) - [cli.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s1-oneflow/batch-sce-s1-oneflow-ns-cubic-sce-twin_codel_af-50Mbit-20ms.tcpdump_cli_cli.r.pcap.xz) - [srv.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s1-oneflow/batch-sce-s1-oneflow-ns-cubic-sce-twin_codel_af-50Mbit-20ms.tcpdump_srv_srv.l.pcap.xz) - [teardown](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s1-oneflow/batch-sce-s1-oneflow-ns-cubic-sce-twin_codel_af-50Mbit-20ms.teardown.log) | [plot](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s1-oneflow/l4s-s1-oneflow-ns-prague-dualpi2-50Mbit-20ms_tcp_delivery_with_rtt.svg) - [cli.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s1-oneflow/batch-l4s-s1-oneflow-ns-prague-dualpi2-50Mbit-20ms.tcpdump_cli_cli.r.pcap.xz) - [srv.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s1-oneflow/batch-l4s-s1-oneflow-ns-prague-dualpi2-50Mbit-20ms.tcpdump_srv_srv.l.pcap.xz) - [teardown](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s1-oneflow/batch-l4s-s1-oneflow-ns-prague-dualpi2-50Mbit-20ms.teardown.log)
50Mbit | 80ms | [plot](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s1-oneflow/sce-s1-oneflow-ns-cubic-sce-twin_codel_af-50Mbit-80ms_tcp_delivery_with_rtt.svg) - [cli.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s1-oneflow/batch-sce-s1-oneflow-ns-cubic-sce-twin_codel_af-50Mbit-80ms.tcpdump_cli_cli.r.pcap.xz) - [srv.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s1-oneflow/batch-sce-s1-oneflow-ns-cubic-sce-twin_codel_af-50Mbit-80ms.tcpdump_srv_srv.l.pcap.xz) - [teardown](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s1-oneflow/batch-sce-s1-oneflow-ns-cubic-sce-twin_codel_af-50Mbit-80ms.teardown.log) | [plot](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s1-oneflow/l4s-s1-oneflow-ns-prague-dualpi2-50Mbit-80ms_tcp_delivery_with_rtt.svg) - [cli.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s1-oneflow/batch-l4s-s1-oneflow-ns-prague-dualpi2-50Mbit-80ms.tcpdump_cli_cli.r.pcap.xz) - [srv.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s1-oneflow/batch-l4s-s1-oneflow-ns-prague-dualpi2-50Mbit-80ms.tcpdump_srv_srv.l.pcap.xz) - [teardown](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s1-oneflow/batch-l4s-s1-oneflow-ns-prague-dualpi2-50Mbit-80ms.teardown.log)
50Mbit | 160ms | [plot](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s1-oneflow/sce-s1-oneflow-ns-cubic-sce-twin_codel_af-50Mbit-160ms_tcp_delivery_with_rtt.svg) - [cli.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s1-oneflow/batch-sce-s1-oneflow-ns-cubic-sce-twin_codel_af-50Mbit-160ms.tcpdump_cli_cli.r.pcap.xz) - [srv.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s1-oneflow/batch-sce-s1-oneflow-ns-cubic-sce-twin_codel_af-50Mbit-160ms.tcpdump_srv_srv.l.pcap.xz) - [teardown](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s1-oneflow/batch-sce-s1-oneflow-ns-cubic-sce-twin_codel_af-50Mbit-160ms.teardown.log) | [plot](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s1-oneflow/l4s-s1-oneflow-ns-prague-dualpi2-50Mbit-160ms_tcp_delivery_with_rtt.svg) - [cli.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s1-oneflow/batch-l4s-s1-oneflow-ns-prague-dualpi2-50Mbit-160ms.tcpdump_cli_cli.r.pcap.xz) - [srv.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s1-oneflow/batch-l4s-s1-oneflow-ns-prague-dualpi2-50Mbit-160ms.tcpdump_srv_srv.l.pcap.xz) - [teardown](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s1-oneflow/batch-l4s-s1-oneflow-ns-prague-dualpi2-50Mbit-160ms.teardown.log)
250Mbit | 20ms | [plot](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s1-oneflow/sce-s1-oneflow-ns-cubic-sce-twin_codel_af-250Mbit-20ms_tcp_delivery_with_rtt.svg) - [cli.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s1-oneflow/batch-sce-s1-oneflow-ns-cubic-sce-twin_codel_af-250Mbit-20ms.tcpdump_cli_cli.r.pcap.xz) - [srv.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s1-oneflow/batch-sce-s1-oneflow-ns-cubic-sce-twin_codel_af-250Mbit-20ms.tcpdump_srv_srv.l.pcap.xz) - [teardown](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s1-oneflow/batch-sce-s1-oneflow-ns-cubic-sce-twin_codel_af-250Mbit-20ms.teardown.log) | [plot](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s1-oneflow/l4s-s1-oneflow-ns-prague-dualpi2-250Mbit-20ms_tcp_delivery_with_rtt.svg) - [cli.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s1-oneflow/batch-l4s-s1-oneflow-ns-prague-dualpi2-250Mbit-20ms.tcpdump_cli_cli.r.pcap.xz) - [srv.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s1-oneflow/batch-l4s-s1-oneflow-ns-prague-dualpi2-250Mbit-20ms.tcpdump_srv_srv.l.pcap.xz) - [teardown](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s1-oneflow/batch-l4s-s1-oneflow-ns-prague-dualpi2-250Mbit-20ms.teardown.log)
250Mbit | 80ms | [plot](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s1-oneflow/sce-s1-oneflow-ns-cubic-sce-twin_codel_af-250Mbit-80ms_tcp_delivery_with_rtt.svg) - [cli.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s1-oneflow/batch-sce-s1-oneflow-ns-cubic-sce-twin_codel_af-250Mbit-80ms.tcpdump_cli_cli.r.pcap.xz) - [srv.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s1-oneflow/batch-sce-s1-oneflow-ns-cubic-sce-twin_codel_af-250Mbit-80ms.tcpdump_srv_srv.l.pcap.xz) - [teardown](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s1-oneflow/batch-sce-s1-oneflow-ns-cubic-sce-twin_codel_af-250Mbit-80ms.teardown.log) | [plot](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s1-oneflow/l4s-s1-oneflow-ns-prague-dualpi2-250Mbit-80ms_tcp_delivery_with_rtt.svg) - [cli.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s1-oneflow/batch-l4s-s1-oneflow-ns-prague-dualpi2-250Mbit-80ms.tcpdump_cli_cli.r.pcap.xz) - [srv.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s1-oneflow/batch-l4s-s1-oneflow-ns-prague-dualpi2-250Mbit-80ms.tcpdump_srv_srv.l.pcap.xz) - [teardown](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s1-oneflow/batch-l4s-s1-oneflow-ns-prague-dualpi2-250Mbit-80ms.teardown.log)
250Mbit | 160ms | [plot](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s1-oneflow/sce-s1-oneflow-ns-cubic-sce-twin_codel_af-250Mbit-160ms_tcp_delivery_with_rtt.svg) - [cli.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s1-oneflow/batch-sce-s1-oneflow-ns-cubic-sce-twin_codel_af-250Mbit-160ms.tcpdump_cli_cli.r.pcap.xz) - [srv.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s1-oneflow/batch-sce-s1-oneflow-ns-cubic-sce-twin_codel_af-250Mbit-160ms.tcpdump_srv_srv.l.pcap.xz) - [teardown](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s1-oneflow/batch-sce-s1-oneflow-ns-cubic-sce-twin_codel_af-250Mbit-160ms.teardown.log) | [plot](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s1-oneflow/l4s-s1-oneflow-ns-prague-dualpi2-250Mbit-160ms_tcp_delivery_with_rtt.svg) - [cli.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s1-oneflow/batch-l4s-s1-oneflow-ns-prague-dualpi2-250Mbit-160ms.tcpdump_cli_cli.r.pcap.xz) - [srv.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s1-oneflow/batch-l4s-s1-oneflow-ns-prague-dualpi2-250Mbit-160ms.tcpdump_srv_srv.l.pcap.xz) - [teardown](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s1-oneflow/batch-l4s-s1-oneflow-ns-prague-dualpi2-250Mbit-160ms.teardown.log)

### Scenario 2: Two Flow Competition

RTT | qdisc | [SCE](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/)
--- | ----- | --------------------------------------------------------------------------
20ms | codel1q | [plot](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/sce-s2-twoflow-ns-cubic-vs-cubic-sce-codel1q-20ms_tcp_delivery_with_rtt.svg) - [cli.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/batch-sce-s2-twoflow-ns-cubic-vs-cubic-sce-codel1q-20ms.tcpdump_cli_cli.r.pcap.xz) - [srv.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/batch-sce-s2-twoflow-ns-cubic-vs-cubic-sce-codel1q-20ms.tcpdump_srv_srv.l.pcap.xz) - [teardown](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/batch-sce-s2-twoflow-ns-cubic-vs-cubic-sce-codel1q-20ms.teardown.log)
80ms | codel1q | [plot](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/sce-s2-twoflow-ns-cubic-vs-cubic-sce-codel1q-80ms_tcp_delivery_with_rtt.svg) - [cli.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/batch-sce-s2-twoflow-ns-cubic-vs-cubic-sce-codel1q-80ms.tcpdump_cli_cli.r.pcap.xz) - [srv.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/batch-sce-s2-twoflow-ns-cubic-vs-cubic-sce-codel1q-80ms.tcpdump_srv_srv.l.pcap.xz) - [teardown](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/batch-sce-s2-twoflow-ns-cubic-vs-cubic-sce-codel1q-80ms.teardown.log)
160ms | codel1q | [plot](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/sce-s2-twoflow-ns-cubic-vs-cubic-sce-codel1q-160ms_tcp_delivery_with_rtt.svg) - [cli.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/batch-sce-s2-twoflow-ns-cubic-vs-cubic-sce-codel1q-160ms.tcpdump_cli_cli.r.pcap.xz) - [srv.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/batch-sce-s2-twoflow-ns-cubic-vs-cubic-sce-codel1q-160ms.tcpdump_srv_srv.l.pcap.xz) - [teardown](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/batch-sce-s2-twoflow-ns-cubic-vs-cubic-sce-codel1q-160ms.teardown.log)
20ms | codel1q(40ms) | [plot](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/sce-s2-twoflow-ns-cubic-vs-cubic-sce-codel1q_40ms_-20ms_tcp_delivery_with_rtt.svg) - [cli.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/batch-sce-s2-twoflow-ns-cubic-vs-cubic-sce-codel1q_40ms_-20ms.tcpdump_cli_cli.r.pcap.xz) - [srv.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/batch-sce-s2-twoflow-ns-cubic-vs-cubic-sce-codel1q_40ms_-20ms.tcpdump_srv_srv.l.pcap.xz) - [teardown](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/batch-sce-s2-twoflow-ns-cubic-vs-cubic-sce-codel1q_40ms_-20ms.teardown.log)
80ms | codel1q(40ms) | [plot](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/sce-s2-twoflow-ns-cubic-vs-cubic-sce-codel1q_40ms_-80ms_tcp_delivery_with_rtt.svg) - [cli.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/batch-sce-s2-twoflow-ns-cubic-vs-cubic-sce-codel1q_40ms_-80ms.tcpdump_cli_cli.r.pcap.xz) - [srv.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/batch-sce-s2-twoflow-ns-cubic-vs-cubic-sce-codel1q_40ms_-80ms.tcpdump_srv_srv.l.pcap.xz) - [teardown](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/batch-sce-s2-twoflow-ns-cubic-vs-cubic-sce-codel1q_40ms_-80ms.teardown.log)
160ms | codel1q(40ms) | [plot](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/sce-s2-twoflow-ns-cubic-vs-cubic-sce-codel1q_40ms_-160ms_tcp_delivery_with_rtt.svg) - [cli.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/batch-sce-s2-twoflow-ns-cubic-vs-cubic-sce-codel1q_40ms_-160ms.tcpdump_cli_cli.r.pcap.xz) - [srv.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/batch-sce-s2-twoflow-ns-cubic-vs-cubic-sce-codel1q_40ms_-160ms.tcpdump_srv_srv.l.pcap.xz) - [teardown](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/batch-sce-s2-twoflow-ns-cubic-vs-cubic-sce-codel1q_40ms_-160ms.teardown.log)
20ms | codel1q(20ms) | [plot](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/sce-s2-twoflow-ns-cubic-vs-cubic-sce-codel1q_20ms_-20ms_tcp_delivery_with_rtt.svg) - [cli.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/batch-sce-s2-twoflow-ns-cubic-vs-cubic-sce-codel1q_20ms_-20ms.tcpdump_cli_cli.r.pcap.xz) - [srv.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/batch-sce-s2-twoflow-ns-cubic-vs-cubic-sce-codel1q_20ms_-20ms.tcpdump_srv_srv.l.pcap.xz) - [teardown](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/batch-sce-s2-twoflow-ns-cubic-vs-cubic-sce-codel1q_20ms_-20ms.teardown.log)
80ms | codel1q(20ms) | [plot](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/sce-s2-twoflow-ns-cubic-vs-cubic-sce-codel1q_20ms_-80ms_tcp_delivery_with_rtt.svg) - [cli.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/batch-sce-s2-twoflow-ns-cubic-vs-cubic-sce-codel1q_20ms_-80ms.tcpdump_cli_cli.r.pcap.xz) - [srv.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/batch-sce-s2-twoflow-ns-cubic-vs-cubic-sce-codel1q_20ms_-80ms.tcpdump_srv_srv.l.pcap.xz) - [teardown](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/batch-sce-s2-twoflow-ns-cubic-vs-cubic-sce-codel1q_20ms_-80ms.teardown.log)
160ms | codel1q(20ms) | [plot](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/sce-s2-twoflow-ns-cubic-vs-cubic-sce-codel1q_20ms_-160ms_tcp_delivery_with_rtt.svg) - [cli.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/batch-sce-s2-twoflow-ns-cubic-vs-cubic-sce-codel1q_20ms_-160ms.tcpdump_cli_cli.r.pcap.xz) - [srv.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/batch-sce-s2-twoflow-ns-cubic-vs-cubic-sce-codel1q_20ms_-160ms.tcpdump_srv_srv.l.pcap.xz) - [teardown](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/batch-sce-s2-twoflow-ns-cubic-vs-cubic-sce-codel1q_20ms_-160ms.teardown.log)
20ms | lfq_cobalt | [plot](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/sce-s2-twoflow-ns-cubic-vs-cubic-sce-lfq_cobalt-20ms_tcp_delivery_with_rtt.svg) - [cli.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/batch-sce-s2-twoflow-ns-cubic-vs-cubic-sce-lfq_cobalt-20ms.tcpdump_cli_cli.r.pcap.xz) - [srv.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/batch-sce-s2-twoflow-ns-cubic-vs-cubic-sce-lfq_cobalt-20ms.tcpdump_srv_srv.l.pcap.xz) - [teardown](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/batch-sce-s2-twoflow-ns-cubic-vs-cubic-sce-lfq_cobalt-20ms.teardown.log)
80ms | lfq_cobalt | [plot](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/sce-s2-twoflow-ns-cubic-vs-cubic-sce-lfq_cobalt-80ms_tcp_delivery_with_rtt.svg) - [cli.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/batch-sce-s2-twoflow-ns-cubic-vs-cubic-sce-lfq_cobalt-80ms.tcpdump_cli_cli.r.pcap.xz) - [srv.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/batch-sce-s2-twoflow-ns-cubic-vs-cubic-sce-lfq_cobalt-80ms.tcpdump_srv_srv.l.pcap.xz) - [teardown](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/batch-sce-s2-twoflow-ns-cubic-vs-cubic-sce-lfq_cobalt-80ms.teardown.log)
160ms | lfq_cobalt | [plot](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/sce-s2-twoflow-ns-cubic-vs-cubic-sce-lfq_cobalt-160ms_tcp_delivery_with_rtt.svg) - [cli.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/batch-sce-s2-twoflow-ns-cubic-vs-cubic-sce-lfq_cobalt-160ms.tcpdump_cli_cli.r.pcap.xz) - [srv.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/batch-sce-s2-twoflow-ns-cubic-vs-cubic-sce-lfq_cobalt-160ms.tcpdump_srv_srv.l.pcap.xz) - [teardown](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/batch-sce-s2-twoflow-ns-cubic-vs-cubic-sce-lfq_cobalt-160ms.teardown.log)
20ms | pfifo(1000) | [plot](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/sce-s2-twoflow-ns-cubic-vs-cubic-sce-pfifo_1000_-20ms_tcp_delivery_with_rtt.svg) - [cli.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/batch-sce-s2-twoflow-ns-cubic-vs-cubic-sce-pfifo_1000_-20ms.tcpdump_cli_cli.r.pcap.xz) - [srv.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/batch-sce-s2-twoflow-ns-cubic-vs-cubic-sce-pfifo_1000_-20ms.tcpdump_srv_srv.l.pcap.xz) - [teardown](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/batch-sce-s2-twoflow-ns-cubic-vs-cubic-sce-pfifo_1000_-20ms.teardown.log)
80ms | pfifo(1000) | [plot](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/sce-s2-twoflow-ns-cubic-vs-cubic-sce-pfifo_1000_-80ms_tcp_delivery_with_rtt.svg) - [cli.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/batch-sce-s2-twoflow-ns-cubic-vs-cubic-sce-pfifo_1000_-80ms.tcpdump_cli_cli.r.pcap.xz) - [srv.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/batch-sce-s2-twoflow-ns-cubic-vs-cubic-sce-pfifo_1000_-80ms.tcpdump_srv_srv.l.pcap.xz) - [teardown](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/batch-sce-s2-twoflow-ns-cubic-vs-cubic-sce-pfifo_1000_-80ms.teardown.log)
160ms | pfifo(1000) | [plot](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/sce-s2-twoflow-ns-cubic-vs-cubic-sce-pfifo_1000_-160ms_tcp_delivery_with_rtt.svg) - [cli.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/batch-sce-s2-twoflow-ns-cubic-vs-cubic-sce-pfifo_1000_-160ms.tcpdump_cli_cli.r.pcap.xz) - [srv.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/batch-sce-s2-twoflow-ns-cubic-vs-cubic-sce-pfifo_1000_-160ms.tcpdump_srv_srv.l.pcap.xz) - [teardown](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/batch-sce-s2-twoflow-ns-cubic-vs-cubic-sce-pfifo_1000_-160ms.teardown.log)
20ms | pfifo(50) | [plot](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/sce-s2-twoflow-ns-cubic-vs-cubic-sce-pfifo_50_-20ms_tcp_delivery_with_rtt.svg) - [cli.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/batch-sce-s2-twoflow-ns-cubic-vs-cubic-sce-pfifo_50_-20ms.tcpdump_cli_cli.r.pcap.xz) - [srv.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/batch-sce-s2-twoflow-ns-cubic-vs-cubic-sce-pfifo_50_-20ms.tcpdump_srv_srv.l.pcap.xz) - [teardown](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/batch-sce-s2-twoflow-ns-cubic-vs-cubic-sce-pfifo_50_-20ms.teardown.log)
80ms | pfifo(50) | [plot](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/sce-s2-twoflow-ns-cubic-vs-cubic-sce-pfifo_50_-80ms_tcp_delivery_with_rtt.svg) - [cli.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/batch-sce-s2-twoflow-ns-cubic-vs-cubic-sce-pfifo_50_-80ms.tcpdump_cli_cli.r.pcap.xz) - [srv.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/batch-sce-s2-twoflow-ns-cubic-vs-cubic-sce-pfifo_50_-80ms.tcpdump_srv_srv.l.pcap.xz) - [teardown](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/batch-sce-s2-twoflow-ns-cubic-vs-cubic-sce-pfifo_50_-80ms.teardown.log)
160ms | pfifo(50) | [plot](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/sce-s2-twoflow-ns-cubic-vs-cubic-sce-pfifo_50_-160ms_tcp_delivery_with_rtt.svg) - [cli.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/batch-sce-s2-twoflow-ns-cubic-vs-cubic-sce-pfifo_50_-160ms.tcpdump_cli_cli.r.pcap.xz) - [srv.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/batch-sce-s2-twoflow-ns-cubic-vs-cubic-sce-pfifo_50_-160ms.tcpdump_srv_srv.l.pcap.xz) - [teardown](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/batch-sce-s2-twoflow-ns-cubic-vs-cubic-sce-pfifo_50_-160ms.teardown.log)
20ms | pie | [plot](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/sce-s2-twoflow-ns-cubic-vs-cubic-sce-pie-20ms_tcp_delivery_with_rtt.svg) - [cli.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/batch-sce-s2-twoflow-ns-cubic-vs-cubic-sce-pie-20ms.tcpdump_cli_cli.r.pcap.xz) - [srv.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/batch-sce-s2-twoflow-ns-cubic-vs-cubic-sce-pie-20ms.tcpdump_srv_srv.l.pcap.xz) - [teardown](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/batch-sce-s2-twoflow-ns-cubic-vs-cubic-sce-pie-20ms.teardown.log)
80ms | pie | [plot](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/sce-s2-twoflow-ns-cubic-vs-cubic-sce-pie-80ms_tcp_delivery_with_rtt.svg) - [cli.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/batch-sce-s2-twoflow-ns-cubic-vs-cubic-sce-pie-80ms.tcpdump_cli_cli.r.pcap.xz) - [srv.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/batch-sce-s2-twoflow-ns-cubic-vs-cubic-sce-pie-80ms.tcpdump_srv_srv.l.pcap.xz) - [teardown](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/batch-sce-s2-twoflow-ns-cubic-vs-cubic-sce-pie-80ms.teardown.log)
160ms | pie | [plot](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/sce-s2-twoflow-ns-cubic-vs-cubic-sce-pie-160ms_tcp_delivery_with_rtt.svg) - [cli.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/batch-sce-s2-twoflow-ns-cubic-vs-cubic-sce-pie-160ms.tcpdump_cli_cli.r.pcap.xz) - [srv.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/batch-sce-s2-twoflow-ns-cubic-vs-cubic-sce-pie-160ms.tcpdump_srv_srv.l.pcap.xz) - [teardown](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/batch-sce-s2-twoflow-ns-cubic-vs-cubic-sce-pie-160ms.teardown.log)
20ms | pie(1000p/20ms) | [plot](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/sce-s2-twoflow-ns-cubic-vs-cubic-sce-pie_1000p_20ms_-20ms_tcp_delivery_with_rtt.svg) - [cli.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/batch-sce-s2-twoflow-ns-cubic-vs-cubic-sce-pie_1000p_20ms_-20ms.tcpdump_cli_cli.r.pcap.xz) - [srv.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/batch-sce-s2-twoflow-ns-cubic-vs-cubic-sce-pie_1000p_20ms_-20ms.tcpdump_srv_srv.l.pcap.xz) - [teardown](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/batch-sce-s2-twoflow-ns-cubic-vs-cubic-sce-pie_1000p_20ms_-20ms.teardown.log)
80ms | pie(1000p/20ms) | [plot](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/sce-s2-twoflow-ns-cubic-vs-cubic-sce-pie_1000p_20ms_-80ms_tcp_delivery_with_rtt.svg) - [cli.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/batch-sce-s2-twoflow-ns-cubic-vs-cubic-sce-pie_1000p_20ms_-80ms.tcpdump_cli_cli.r.pcap.xz) - [srv.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/batch-sce-s2-twoflow-ns-cubic-vs-cubic-sce-pie_1000p_20ms_-80ms.tcpdump_srv_srv.l.pcap.xz) - [teardown](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/batch-sce-s2-twoflow-ns-cubic-vs-cubic-sce-pie_1000p_20ms_-80ms.teardown.log)
160ms | pie(1000p/20ms) | [plot](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/sce-s2-twoflow-ns-cubic-vs-cubic-sce-pie_1000p_20ms_-160ms_tcp_delivery_with_rtt.svg) - [cli.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/batch-sce-s2-twoflow-ns-cubic-vs-cubic-sce-pie_1000p_20ms_-160ms.tcpdump_cli_cli.r.pcap.xz) - [srv.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/batch-sce-s2-twoflow-ns-cubic-vs-cubic-sce-pie_1000p_20ms_-160ms.tcpdump_srv_srv.l.pcap.xz) - [teardown](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/batch-sce-s2-twoflow-ns-cubic-vs-cubic-sce-pie_1000p_20ms_-160ms.teardown.log)
20ms | pie(100p/20ms) | [plot](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/sce-s2-twoflow-ns-cubic-vs-cubic-sce-pie_100p_20ms_-20ms_tcp_delivery_with_rtt.svg) - [cli.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/batch-sce-s2-twoflow-ns-cubic-vs-cubic-sce-pie_100p_20ms_-20ms.tcpdump_cli_cli.r.pcap.xz) - [srv.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/batch-sce-s2-twoflow-ns-cubic-vs-cubic-sce-pie_100p_20ms_-20ms.tcpdump_srv_srv.l.pcap.xz) - [teardown](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/batch-sce-s2-twoflow-ns-cubic-vs-cubic-sce-pie_100p_20ms_-20ms.teardown.log)
80ms | pie(100p/20ms) | [plot](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/sce-s2-twoflow-ns-cubic-vs-cubic-sce-pie_100p_20ms_-80ms_tcp_delivery_with_rtt.svg) - [cli.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/batch-sce-s2-twoflow-ns-cubic-vs-cubic-sce-pie_100p_20ms_-80ms.tcpdump_cli_cli.r.pcap.xz) - [srv.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/batch-sce-s2-twoflow-ns-cubic-vs-cubic-sce-pie_100p_20ms_-80ms.tcpdump_srv_srv.l.pcap.xz) - [teardown](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/batch-sce-s2-twoflow-ns-cubic-vs-cubic-sce-pie_100p_20ms_-80ms.teardown.log)
160ms | pie(100p/20ms) | [plot](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/sce-s2-twoflow-ns-cubic-vs-cubic-sce-pie_100p_20ms_-160ms_tcp_delivery_with_rtt.svg) - [cli.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/batch-sce-s2-twoflow-ns-cubic-vs-cubic-sce-pie_100p_20ms_-160ms.tcpdump_cli_cli.r.pcap.xz) - [srv.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/batch-sce-s2-twoflow-ns-cubic-vs-cubic-sce-pie_100p_20ms_-160ms.tcpdump_srv_srv.l.pcap.xz) - [teardown](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/batch-sce-s2-twoflow-ns-cubic-vs-cubic-sce-pie_100p_20ms_-160ms.teardown.log)
20ms | pie(100p/5ms) | [plot](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/sce-s2-twoflow-ns-cubic-vs-cubic-sce-pie_100p_5ms_-20ms_tcp_delivery_with_rtt.svg) - [cli.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/batch-sce-s2-twoflow-ns-cubic-vs-cubic-sce-pie_100p_5ms_-20ms.tcpdump_cli_cli.r.pcap.xz) - [srv.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/batch-sce-s2-twoflow-ns-cubic-vs-cubic-sce-pie_100p_5ms_-20ms.tcpdump_srv_srv.l.pcap.xz) - [teardown](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/batch-sce-s2-twoflow-ns-cubic-vs-cubic-sce-pie_100p_5ms_-20ms.teardown.log)
80ms | pie(100p/5ms) | [plot](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/sce-s2-twoflow-ns-cubic-vs-cubic-sce-pie_100p_5ms_-80ms_tcp_delivery_with_rtt.svg) - [cli.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/batch-sce-s2-twoflow-ns-cubic-vs-cubic-sce-pie_100p_5ms_-80ms.tcpdump_cli_cli.r.pcap.xz) - [srv.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/batch-sce-s2-twoflow-ns-cubic-vs-cubic-sce-pie_100p_5ms_-80ms.tcpdump_srv_srv.l.pcap.xz) - [teardown](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/batch-sce-s2-twoflow-ns-cubic-vs-cubic-sce-pie_100p_5ms_-80ms.teardown.log)
160ms | pie(100p/5ms) | [plot](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/sce-s2-twoflow-ns-cubic-vs-cubic-sce-pie_100p_5ms_-160ms_tcp_delivery_with_rtt.svg) - [cli.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/batch-sce-s2-twoflow-ns-cubic-vs-cubic-sce-pie_100p_5ms_-160ms.tcpdump_cli_cli.r.pcap.xz) - [srv.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/batch-sce-s2-twoflow-ns-cubic-vs-cubic-sce-pie_100p_5ms_-160ms.tcpdump_srv_srv.l.pcap.xz) - [teardown](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/batch-sce-s2-twoflow-ns-cubic-vs-cubic-sce-pie_100p_5ms_-160ms.teardown.log)
20ms | pie(noecn) | [plot](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/sce-s2-twoflow-ns-cubic-vs-cubic-sce-pie_noecn_-20ms_tcp_delivery_with_rtt.svg) - [cli.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/batch-sce-s2-twoflow-ns-cubic-vs-cubic-sce-pie_noecn_-20ms.tcpdump_cli_cli.r.pcap.xz) - [srv.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/batch-sce-s2-twoflow-ns-cubic-vs-cubic-sce-pie_noecn_-20ms.tcpdump_srv_srv.l.pcap.xz) - [teardown](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/batch-sce-s2-twoflow-ns-cubic-vs-cubic-sce-pie_noecn_-20ms.teardown.log)
80ms | pie(noecn) | [plot](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/sce-s2-twoflow-ns-cubic-vs-cubic-sce-pie_noecn_-80ms_tcp_delivery_with_rtt.svg) - [cli.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/batch-sce-s2-twoflow-ns-cubic-vs-cubic-sce-pie_noecn_-80ms.tcpdump_cli_cli.r.pcap.xz) - [srv.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/batch-sce-s2-twoflow-ns-cubic-vs-cubic-sce-pie_noecn_-80ms.tcpdump_srv_srv.l.pcap.xz) - [teardown](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/batch-sce-s2-twoflow-ns-cubic-vs-cubic-sce-pie_noecn_-80ms.teardown.log)
160ms | pie(noecn) | [plot](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/sce-s2-twoflow-ns-cubic-vs-cubic-sce-pie_noecn_-160ms_tcp_delivery_with_rtt.svg) - [cli.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/batch-sce-s2-twoflow-ns-cubic-vs-cubic-sce-pie_noecn_-160ms.tcpdump_cli_cli.r.pcap.xz) - [srv.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/batch-sce-s2-twoflow-ns-cubic-vs-cubic-sce-pie_noecn_-160ms.tcpdump_srv_srv.l.pcap.xz) - [teardown](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/batch-sce-s2-twoflow-ns-cubic-vs-cubic-sce-pie_noecn_-160ms.teardown.log)
20ms | red(150000) | [plot](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/sce-s2-twoflow-ns-cubic-vs-cubic-sce-red_150000_-20ms_tcp_delivery_with_rtt.svg) - [cli.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/batch-sce-s2-twoflow-ns-cubic-vs-cubic-sce-red_150000_-20ms.tcpdump_cli_cli.r.pcap.xz) - [srv.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/batch-sce-s2-twoflow-ns-cubic-vs-cubic-sce-red_150000_-20ms.tcpdump_srv_srv.l.pcap.xz) - [teardown](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/batch-sce-s2-twoflow-ns-cubic-vs-cubic-sce-red_150000_-20ms.teardown.log)
80ms | red(150000) | [plot](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/sce-s2-twoflow-ns-cubic-vs-cubic-sce-red_150000_-80ms_tcp_delivery_with_rtt.svg) - [cli.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/batch-sce-s2-twoflow-ns-cubic-vs-cubic-sce-red_150000_-80ms.tcpdump_cli_cli.r.pcap.xz) - [srv.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/batch-sce-s2-twoflow-ns-cubic-vs-cubic-sce-red_150000_-80ms.tcpdump_srv_srv.l.pcap.xz) - [teardown](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/batch-sce-s2-twoflow-ns-cubic-vs-cubic-sce-red_150000_-80ms.teardown.log)
160ms | red(150000) | [plot](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/sce-s2-twoflow-ns-cubic-vs-cubic-sce-red_150000_-160ms_tcp_delivery_with_rtt.svg) - [cli.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/batch-sce-s2-twoflow-ns-cubic-vs-cubic-sce-red_150000_-160ms.tcpdump_cli_cli.r.pcap.xz) - [srv.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/batch-sce-s2-twoflow-ns-cubic-vs-cubic-sce-red_150000_-160ms.tcpdump_srv_srv.l.pcap.xz) - [teardown](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/batch-sce-s2-twoflow-ns-cubic-vs-cubic-sce-red_150000_-160ms.teardown.log)
20ms | red(400000) | [plot](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/sce-s2-twoflow-ns-cubic-vs-cubic-sce-red_400000_-20ms_tcp_delivery_with_rtt.svg) - [cli.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/batch-sce-s2-twoflow-ns-cubic-vs-cubic-sce-red_400000_-20ms.tcpdump_cli_cli.r.pcap.xz) - [srv.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/batch-sce-s2-twoflow-ns-cubic-vs-cubic-sce-red_400000_-20ms.tcpdump_srv_srv.l.pcap.xz) - [teardown](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/batch-sce-s2-twoflow-ns-cubic-vs-cubic-sce-red_400000_-20ms.teardown.log)
80ms | red(400000) | [plot](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/sce-s2-twoflow-ns-cubic-vs-cubic-sce-red_400000_-80ms_tcp_delivery_with_rtt.svg) - [cli.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/batch-sce-s2-twoflow-ns-cubic-vs-cubic-sce-red_400000_-80ms.tcpdump_cli_cli.r.pcap.xz) - [srv.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/batch-sce-s2-twoflow-ns-cubic-vs-cubic-sce-red_400000_-80ms.tcpdump_srv_srv.l.pcap.xz) - [teardown](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/batch-sce-s2-twoflow-ns-cubic-vs-cubic-sce-red_400000_-80ms.teardown.log)
160ms | red(400000) | [plot](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/sce-s2-twoflow-ns-cubic-vs-cubic-sce-red_400000_-160ms_tcp_delivery_with_rtt.svg) - [cli.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/batch-sce-s2-twoflow-ns-cubic-vs-cubic-sce-red_400000_-160ms.tcpdump_cli_cli.r.pcap.xz) - [srv.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/batch-sce-s2-twoflow-ns-cubic-vs-cubic-sce-red_400000_-160ms.tcpdump_srv_srv.l.pcap.xz) - [teardown](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/batch-sce-s2-twoflow-ns-cubic-vs-cubic-sce-red_400000_-160ms.teardown.log)
20ms | twin_codel_af | [plot](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/sce-s2-twoflow-ns-cubic-vs-cubic-sce-twin_codel_af-20ms_tcp_delivery_with_rtt.svg) - [cli.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/batch-sce-s2-twoflow-ns-cubic-vs-cubic-sce-twin_codel_af-20ms.tcpdump_cli_cli.r.pcap.xz) - [srv.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/batch-sce-s2-twoflow-ns-cubic-vs-cubic-sce-twin_codel_af-20ms.tcpdump_srv_srv.l.pcap.xz) - [teardown](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/batch-sce-s2-twoflow-ns-cubic-vs-cubic-sce-twin_codel_af-20ms.teardown.log)
80ms | twin_codel_af | [plot](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/sce-s2-twoflow-ns-cubic-vs-cubic-sce-twin_codel_af-80ms_tcp_delivery_with_rtt.svg) - [cli.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/batch-sce-s2-twoflow-ns-cubic-vs-cubic-sce-twin_codel_af-80ms.tcpdump_cli_cli.r.pcap.xz) - [srv.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/batch-sce-s2-twoflow-ns-cubic-vs-cubic-sce-twin_codel_af-80ms.tcpdump_srv_srv.l.pcap.xz) - [teardown](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/batch-sce-s2-twoflow-ns-cubic-vs-cubic-sce-twin_codel_af-80ms.teardown.log)
160ms | twin_codel_af | [plot](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/sce-s2-twoflow-ns-cubic-vs-cubic-sce-twin_codel_af-160ms_tcp_delivery_with_rtt.svg) - [cli.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/batch-sce-s2-twoflow-ns-cubic-vs-cubic-sce-twin_codel_af-160ms.tcpdump_cli_cli.r.pcap.xz) - [srv.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/batch-sce-s2-twoflow-ns-cubic-vs-cubic-sce-twin_codel_af-160ms.tcpdump_srv_srv.l.pcap.xz) - [teardown](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s2-twoflow/batch-sce-s2-twoflow-ns-cubic-vs-cubic-sce-twin_codel_af-160ms.teardown.log)

RTT | qdisc | [L4S](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/)
--- | ----- | --------------------------------------------------------------------------
20ms | codel1q | [plot](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/l4s-s2-twoflow-ns-cubic-vs-prague-codel1q-20ms_tcp_delivery_with_rtt.svg) - [cli.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/batch-l4s-s2-twoflow-ns-cubic-vs-prague-codel1q-20ms.tcpdump_cli_cli.r.pcap.xz) - [srv.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/batch-l4s-s2-twoflow-ns-cubic-vs-prague-codel1q-20ms.tcpdump_srv_srv.l.pcap.xz) - [teardown](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/batch-l4s-s2-twoflow-ns-cubic-vs-prague-codel1q-20ms.teardown.log)
80ms | codel1q | [plot](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/l4s-s2-twoflow-ns-cubic-vs-prague-codel1q-80ms_tcp_delivery_with_rtt.svg) - [cli.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/batch-l4s-s2-twoflow-ns-cubic-vs-prague-codel1q-80ms.tcpdump_cli_cli.r.pcap.xz) - [srv.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/batch-l4s-s2-twoflow-ns-cubic-vs-prague-codel1q-80ms.tcpdump_srv_srv.l.pcap.xz) - [teardown](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/batch-l4s-s2-twoflow-ns-cubic-vs-prague-codel1q-80ms.teardown.log)
160ms | codel1q | [plot](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/l4s-s2-twoflow-ns-cubic-vs-prague-codel1q-160ms_tcp_delivery_with_rtt.svg) - [cli.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/batch-l4s-s2-twoflow-ns-cubic-vs-prague-codel1q-160ms.tcpdump_cli_cli.r.pcap.xz) - [srv.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/batch-l4s-s2-twoflow-ns-cubic-vs-prague-codel1q-160ms.tcpdump_srv_srv.l.pcap.xz) - [teardown](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/batch-l4s-s2-twoflow-ns-cubic-vs-prague-codel1q-160ms.teardown.log)
20ms | codel1q(40ms) | [plot](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/l4s-s2-twoflow-ns-cubic-vs-prague-codel1q_40ms_-20ms_tcp_delivery_with_rtt.svg) - [cli.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/batch-l4s-s2-twoflow-ns-cubic-vs-prague-codel1q_40ms_-20ms.tcpdump_cli_cli.r.pcap.xz) - [srv.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/batch-l4s-s2-twoflow-ns-cubic-vs-prague-codel1q_40ms_-20ms.tcpdump_srv_srv.l.pcap.xz) - [teardown](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/batch-l4s-s2-twoflow-ns-cubic-vs-prague-codel1q_40ms_-20ms.teardown.log)
80ms | codel1q(40ms) | [plot](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/l4s-s2-twoflow-ns-cubic-vs-prague-codel1q_40ms_-80ms_tcp_delivery_with_rtt.svg) - [cli.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/batch-l4s-s2-twoflow-ns-cubic-vs-prague-codel1q_40ms_-80ms.tcpdump_cli_cli.r.pcap.xz) - [srv.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/batch-l4s-s2-twoflow-ns-cubic-vs-prague-codel1q_40ms_-80ms.tcpdump_srv_srv.l.pcap.xz) - [teardown](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/batch-l4s-s2-twoflow-ns-cubic-vs-prague-codel1q_40ms_-80ms.teardown.log)
160ms | codel1q(40ms) | [plot](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/l4s-s2-twoflow-ns-cubic-vs-prague-codel1q_40ms_-160ms_tcp_delivery_with_rtt.svg) - [cli.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/batch-l4s-s2-twoflow-ns-cubic-vs-prague-codel1q_40ms_-160ms.tcpdump_cli_cli.r.pcap.xz) - [srv.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/batch-l4s-s2-twoflow-ns-cubic-vs-prague-codel1q_40ms_-160ms.tcpdump_srv_srv.l.pcap.xz) - [teardown](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/batch-l4s-s2-twoflow-ns-cubic-vs-prague-codel1q_40ms_-160ms.teardown.log)
20ms | codel1q(20ms) | [plot](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/l4s-s2-twoflow-ns-cubic-vs-prague-codel1q_20ms_-20ms_tcp_delivery_with_rtt.svg) - [cli.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/batch-l4s-s2-twoflow-ns-cubic-vs-prague-codel1q_20ms_-20ms.tcpdump_cli_cli.r.pcap.xz) - [srv.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/batch-l4s-s2-twoflow-ns-cubic-vs-prague-codel1q_20ms_-20ms.tcpdump_srv_srv.l.pcap.xz) - [teardown](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/batch-l4s-s2-twoflow-ns-cubic-vs-prague-codel1q_20ms_-20ms.teardown.log)
80ms | codel1q(20ms) | [plot](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/l4s-s2-twoflow-ns-cubic-vs-prague-codel1q_20ms_-80ms_tcp_delivery_with_rtt.svg) - [cli.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/batch-l4s-s2-twoflow-ns-cubic-vs-prague-codel1q_20ms_-80ms.tcpdump_cli_cli.r.pcap.xz) - [srv.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/batch-l4s-s2-twoflow-ns-cubic-vs-prague-codel1q_20ms_-80ms.tcpdump_srv_srv.l.pcap.xz) - [teardown](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/batch-l4s-s2-twoflow-ns-cubic-vs-prague-codel1q_20ms_-80ms.teardown.log)
160ms | codel1q(20ms) | [plot](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/l4s-s2-twoflow-ns-cubic-vs-prague-codel1q_20ms_-160ms_tcp_delivery_with_rtt.svg) - [cli.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/batch-l4s-s2-twoflow-ns-cubic-vs-prague-codel1q_20ms_-160ms.tcpdump_cli_cli.r.pcap.xz) - [srv.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/batch-l4s-s2-twoflow-ns-cubic-vs-prague-codel1q_20ms_-160ms.tcpdump_srv_srv.l.pcap.xz) - [teardown](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/batch-l4s-s2-twoflow-ns-cubic-vs-prague-codel1q_20ms_-160ms.teardown.log)
20ms | dualpi2 | [plot](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/l4s-s2-twoflow-ns-cubic-vs-prague-dualpi2-20ms_tcp_delivery_with_rtt.svg) - [cli.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/batch-l4s-s2-twoflow-ns-cubic-vs-prague-dualpi2-20ms.tcpdump_cli_cli.r.pcap.xz) - [srv.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/batch-l4s-s2-twoflow-ns-cubic-vs-prague-dualpi2-20ms.tcpdump_srv_srv.l.pcap.xz) - [teardown](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/batch-l4s-s2-twoflow-ns-cubic-vs-prague-dualpi2-20ms.teardown.log)
80ms | dualpi2 | [plot](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/l4s-s2-twoflow-ns-cubic-vs-prague-dualpi2-80ms_tcp_delivery_with_rtt.svg) - [cli.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/batch-l4s-s2-twoflow-ns-cubic-vs-prague-dualpi2-80ms.tcpdump_cli_cli.r.pcap.xz) - [srv.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/batch-l4s-s2-twoflow-ns-cubic-vs-prague-dualpi2-80ms.tcpdump_srv_srv.l.pcap.xz) - [teardown](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/batch-l4s-s2-twoflow-ns-cubic-vs-prague-dualpi2-80ms.teardown.log)
160ms | dualpi2 | [plot](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/l4s-s2-twoflow-ns-cubic-vs-prague-dualpi2-160ms_tcp_delivery_with_rtt.svg) - [cli.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/batch-l4s-s2-twoflow-ns-cubic-vs-prague-dualpi2-160ms.tcpdump_cli_cli.r.pcap.xz) - [srv.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/batch-l4s-s2-twoflow-ns-cubic-vs-prague-dualpi2-160ms.tcpdump_srv_srv.l.pcap.xz) - [teardown](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/batch-l4s-s2-twoflow-ns-cubic-vs-prague-dualpi2-160ms.teardown.log)
20ms | pfifo(1000) | [plot](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/l4s-s2-twoflow-ns-cubic-vs-prague-pfifo_1000_-20ms_tcp_delivery_with_rtt.svg) - [cli.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/batch-l4s-s2-twoflow-ns-cubic-vs-prague-pfifo_1000_-20ms.tcpdump_cli_cli.r.pcap.xz) - [srv.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/batch-l4s-s2-twoflow-ns-cubic-vs-prague-pfifo_1000_-20ms.tcpdump_srv_srv.l.pcap.xz) - [teardown](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/batch-l4s-s2-twoflow-ns-cubic-vs-prague-pfifo_1000_-20ms.teardown.log)
80ms | pfifo(1000) | [plot](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/l4s-s2-twoflow-ns-cubic-vs-prague-pfifo_1000_-80ms_tcp_delivery_with_rtt.svg) - [cli.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/batch-l4s-s2-twoflow-ns-cubic-vs-prague-pfifo_1000_-80ms.tcpdump_cli_cli.r.pcap.xz) - [srv.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/batch-l4s-s2-twoflow-ns-cubic-vs-prague-pfifo_1000_-80ms.tcpdump_srv_srv.l.pcap.xz) - [teardown](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/batch-l4s-s2-twoflow-ns-cubic-vs-prague-pfifo_1000_-80ms.teardown.log)
160ms | pfifo(1000) | [plot](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/l4s-s2-twoflow-ns-cubic-vs-prague-pfifo_1000_-160ms_tcp_delivery_with_rtt.svg) - [cli.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/batch-l4s-s2-twoflow-ns-cubic-vs-prague-pfifo_1000_-160ms.tcpdump_cli_cli.r.pcap.xz) - [srv.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/batch-l4s-s2-twoflow-ns-cubic-vs-prague-pfifo_1000_-160ms.tcpdump_srv_srv.l.pcap.xz) - [teardown](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/batch-l4s-s2-twoflow-ns-cubic-vs-prague-pfifo_1000_-160ms.teardown.log)
20ms | pfifo(50) | [plot](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/l4s-s2-twoflow-ns-cubic-vs-prague-pfifo_50_-20ms_tcp_delivery_with_rtt.svg) - [cli.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/batch-l4s-s2-twoflow-ns-cubic-vs-prague-pfifo_50_-20ms.tcpdump_cli_cli.r.pcap.xz) - [srv.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/batch-l4s-s2-twoflow-ns-cubic-vs-prague-pfifo_50_-20ms.tcpdump_srv_srv.l.pcap.xz) - [teardown](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/batch-l4s-s2-twoflow-ns-cubic-vs-prague-pfifo_50_-20ms.teardown.log)
80ms | pfifo(50) | [plot](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/l4s-s2-twoflow-ns-cubic-vs-prague-pfifo_50_-80ms_tcp_delivery_with_rtt.svg) - [cli.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/batch-l4s-s2-twoflow-ns-cubic-vs-prague-pfifo_50_-80ms.tcpdump_cli_cli.r.pcap.xz) - [srv.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/batch-l4s-s2-twoflow-ns-cubic-vs-prague-pfifo_50_-80ms.tcpdump_srv_srv.l.pcap.xz) - [teardown](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/batch-l4s-s2-twoflow-ns-cubic-vs-prague-pfifo_50_-80ms.teardown.log)
160ms | pfifo(50) | [plot](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/l4s-s2-twoflow-ns-cubic-vs-prague-pfifo_50_-160ms_tcp_delivery_with_rtt.svg) - [cli.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/batch-l4s-s2-twoflow-ns-cubic-vs-prague-pfifo_50_-160ms.tcpdump_cli_cli.r.pcap.xz) - [srv.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/batch-l4s-s2-twoflow-ns-cubic-vs-prague-pfifo_50_-160ms.tcpdump_srv_srv.l.pcap.xz) - [teardown](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/batch-l4s-s2-twoflow-ns-cubic-vs-prague-pfifo_50_-160ms.teardown.log)
20ms | pie | [plot](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/l4s-s2-twoflow-ns-cubic-vs-prague-pie-20ms_tcp_delivery_with_rtt.svg) - [cli.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/batch-l4s-s2-twoflow-ns-cubic-vs-prague-pie-20ms.tcpdump_cli_cli.r.pcap.xz) - [srv.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/batch-l4s-s2-twoflow-ns-cubic-vs-prague-pie-20ms.tcpdump_srv_srv.l.pcap.xz) - [teardown](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/batch-l4s-s2-twoflow-ns-cubic-vs-prague-pie-20ms.teardown.log)
80ms | pie | [plot](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/l4s-s2-twoflow-ns-cubic-vs-prague-pie-80ms_tcp_delivery_with_rtt.svg) - [cli.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/batch-l4s-s2-twoflow-ns-cubic-vs-prague-pie-80ms.tcpdump_cli_cli.r.pcap.xz) - [srv.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/batch-l4s-s2-twoflow-ns-cubic-vs-prague-pie-80ms.tcpdump_srv_srv.l.pcap.xz) - [teardown](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/batch-l4s-s2-twoflow-ns-cubic-vs-prague-pie-80ms.teardown.log)
160ms | pie | [plot](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/l4s-s2-twoflow-ns-cubic-vs-prague-pie-160ms_tcp_delivery_with_rtt.svg) - [cli.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/batch-l4s-s2-twoflow-ns-cubic-vs-prague-pie-160ms.tcpdump_cli_cli.r.pcap.xz) - [srv.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/batch-l4s-s2-twoflow-ns-cubic-vs-prague-pie-160ms.tcpdump_srv_srv.l.pcap.xz) - [teardown](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/batch-l4s-s2-twoflow-ns-cubic-vs-prague-pie-160ms.teardown.log)
20ms | pie(1000p/20ms) | [plot](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/l4s-s2-twoflow-ns-cubic-vs-prague-pie_1000p_20ms_-20ms_tcp_delivery_with_rtt.svg) - [cli.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/batch-l4s-s2-twoflow-ns-cubic-vs-prague-pie_1000p_20ms_-20ms.tcpdump_cli_cli.r.pcap.xz) - [srv.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/batch-l4s-s2-twoflow-ns-cubic-vs-prague-pie_1000p_20ms_-20ms.tcpdump_srv_srv.l.pcap.xz) - [teardown](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/batch-l4s-s2-twoflow-ns-cubic-vs-prague-pie_1000p_20ms_-20ms.teardown.log)
80ms | pie(1000p/20ms) | [plot](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/l4s-s2-twoflow-ns-cubic-vs-prague-pie_1000p_20ms_-80ms_tcp_delivery_with_rtt.svg) - [cli.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/batch-l4s-s2-twoflow-ns-cubic-vs-prague-pie_1000p_20ms_-80ms.tcpdump_cli_cli.r.pcap.xz) - [srv.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/batch-l4s-s2-twoflow-ns-cubic-vs-prague-pie_1000p_20ms_-80ms.tcpdump_srv_srv.l.pcap.xz) - [teardown](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/batch-l4s-s2-twoflow-ns-cubic-vs-prague-pie_1000p_20ms_-80ms.teardown.log)
160ms | pie(1000p/20ms) | [plot](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/l4s-s2-twoflow-ns-cubic-vs-prague-pie_1000p_20ms_-160ms_tcp_delivery_with_rtt.svg) - [cli.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/batch-l4s-s2-twoflow-ns-cubic-vs-prague-pie_1000p_20ms_-160ms.tcpdump_cli_cli.r.pcap.xz) - [srv.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/batch-l4s-s2-twoflow-ns-cubic-vs-prague-pie_1000p_20ms_-160ms.tcpdump_srv_srv.l.pcap.xz) - [teardown](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/batch-l4s-s2-twoflow-ns-cubic-vs-prague-pie_1000p_20ms_-160ms.teardown.log)
20ms | pie(100p/20ms) | [plot](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/l4s-s2-twoflow-ns-cubic-vs-prague-pie_100p_20ms_-20ms_tcp_delivery_with_rtt.svg) - [cli.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/batch-l4s-s2-twoflow-ns-cubic-vs-prague-pie_100p_20ms_-20ms.tcpdump_cli_cli.r.pcap.xz) - [srv.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/batch-l4s-s2-twoflow-ns-cubic-vs-prague-pie_100p_20ms_-20ms.tcpdump_srv_srv.l.pcap.xz) - [teardown](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/batch-l4s-s2-twoflow-ns-cubic-vs-prague-pie_100p_20ms_-20ms.teardown.log)
80ms | pie(100p/20ms) | [plot](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/l4s-s2-twoflow-ns-cubic-vs-prague-pie_100p_20ms_-80ms_tcp_delivery_with_rtt.svg) - [cli.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/batch-l4s-s2-twoflow-ns-cubic-vs-prague-pie_100p_20ms_-80ms.tcpdump_cli_cli.r.pcap.xz) - [srv.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/batch-l4s-s2-twoflow-ns-cubic-vs-prague-pie_100p_20ms_-80ms.tcpdump_srv_srv.l.pcap.xz) - [teardown](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/batch-l4s-s2-twoflow-ns-cubic-vs-prague-pie_100p_20ms_-80ms.teardown.log)
160ms | pie(100p/20ms) | [plot](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/l4s-s2-twoflow-ns-cubic-vs-prague-pie_100p_20ms_-160ms_tcp_delivery_with_rtt.svg) - [cli.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/batch-l4s-s2-twoflow-ns-cubic-vs-prague-pie_100p_20ms_-160ms.tcpdump_cli_cli.r.pcap.xz) - [srv.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/batch-l4s-s2-twoflow-ns-cubic-vs-prague-pie_100p_20ms_-160ms.tcpdump_srv_srv.l.pcap.xz) - [teardown](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/batch-l4s-s2-twoflow-ns-cubic-vs-prague-pie_100p_20ms_-160ms.teardown.log)
20ms | pie(100p/5ms) | [plot](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/l4s-s2-twoflow-ns-cubic-vs-prague-pie_100p_5ms_-20ms_tcp_delivery_with_rtt.svg) - [cli.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/batch-l4s-s2-twoflow-ns-cubic-vs-prague-pie_100p_5ms_-20ms.tcpdump_cli_cli.r.pcap.xz) - [srv.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/batch-l4s-s2-twoflow-ns-cubic-vs-prague-pie_100p_5ms_-20ms.tcpdump_srv_srv.l.pcap.xz) - [teardown](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/batch-l4s-s2-twoflow-ns-cubic-vs-prague-pie_100p_5ms_-20ms.teardown.log)
80ms | pie(100p/5ms) | [plot](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/l4s-s2-twoflow-ns-cubic-vs-prague-pie_100p_5ms_-80ms_tcp_delivery_with_rtt.svg) - [cli.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/batch-l4s-s2-twoflow-ns-cubic-vs-prague-pie_100p_5ms_-80ms.tcpdump_cli_cli.r.pcap.xz) - [srv.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/batch-l4s-s2-twoflow-ns-cubic-vs-prague-pie_100p_5ms_-80ms.tcpdump_srv_srv.l.pcap.xz) - [teardown](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/batch-l4s-s2-twoflow-ns-cubic-vs-prague-pie_100p_5ms_-80ms.teardown.log)
160ms | pie(100p/5ms) | [plot](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/l4s-s2-twoflow-ns-cubic-vs-prague-pie_100p_5ms_-160ms_tcp_delivery_with_rtt.svg) - [cli.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/batch-l4s-s2-twoflow-ns-cubic-vs-prague-pie_100p_5ms_-160ms.tcpdump_cli_cli.r.pcap.xz) - [srv.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/batch-l4s-s2-twoflow-ns-cubic-vs-prague-pie_100p_5ms_-160ms.tcpdump_srv_srv.l.pcap.xz) - [teardown](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/batch-l4s-s2-twoflow-ns-cubic-vs-prague-pie_100p_5ms_-160ms.teardown.log)
20ms | pie(noecn) | [plot](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/l4s-s2-twoflow-ns-cubic-vs-prague-pie_noecn_-20ms_tcp_delivery_with_rtt.svg) - [cli.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/batch-l4s-s2-twoflow-ns-cubic-vs-prague-pie_noecn_-20ms.tcpdump_cli_cli.r.pcap.xz) - [srv.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/batch-l4s-s2-twoflow-ns-cubic-vs-prague-pie_noecn_-20ms.tcpdump_srv_srv.l.pcap.xz) - [teardown](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/batch-l4s-s2-twoflow-ns-cubic-vs-prague-pie_noecn_-20ms.teardown.log)
80ms | pie(noecn) | [plot](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/l4s-s2-twoflow-ns-cubic-vs-prague-pie_noecn_-80ms_tcp_delivery_with_rtt.svg) - [cli.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/batch-l4s-s2-twoflow-ns-cubic-vs-prague-pie_noecn_-80ms.tcpdump_cli_cli.r.pcap.xz) - [srv.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/batch-l4s-s2-twoflow-ns-cubic-vs-prague-pie_noecn_-80ms.tcpdump_srv_srv.l.pcap.xz) - [teardown](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/batch-l4s-s2-twoflow-ns-cubic-vs-prague-pie_noecn_-80ms.teardown.log)
160ms | pie(noecn) | [plot](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/l4s-s2-twoflow-ns-cubic-vs-prague-pie_noecn_-160ms_tcp_delivery_with_rtt.svg) - [cli.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/batch-l4s-s2-twoflow-ns-cubic-vs-prague-pie_noecn_-160ms.tcpdump_cli_cli.r.pcap.xz) - [srv.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/batch-l4s-s2-twoflow-ns-cubic-vs-prague-pie_noecn_-160ms.tcpdump_srv_srv.l.pcap.xz) - [teardown](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/batch-l4s-s2-twoflow-ns-cubic-vs-prague-pie_noecn_-160ms.teardown.log)
20ms | red(150000) | [plot](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/l4s-s2-twoflow-ns-cubic-vs-prague-red_150000_-20ms_tcp_delivery_with_rtt.svg) - [cli.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/batch-l4s-s2-twoflow-ns-cubic-vs-prague-red_150000_-20ms.tcpdump_cli_cli.r.pcap.xz) - [srv.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/batch-l4s-s2-twoflow-ns-cubic-vs-prague-red_150000_-20ms.tcpdump_srv_srv.l.pcap.xz) - [teardown](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/batch-l4s-s2-twoflow-ns-cubic-vs-prague-red_150000_-20ms.teardown.log)
80ms | red(150000) | [plot](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/l4s-s2-twoflow-ns-cubic-vs-prague-red_150000_-80ms_tcp_delivery_with_rtt.svg) - [cli.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/batch-l4s-s2-twoflow-ns-cubic-vs-prague-red_150000_-80ms.tcpdump_cli_cli.r.pcap.xz) - [srv.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/batch-l4s-s2-twoflow-ns-cubic-vs-prague-red_150000_-80ms.tcpdump_srv_srv.l.pcap.xz) - [teardown](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/batch-l4s-s2-twoflow-ns-cubic-vs-prague-red_150000_-80ms.teardown.log)
160ms | red(150000) | [plot](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/l4s-s2-twoflow-ns-cubic-vs-prague-red_150000_-160ms_tcp_delivery_with_rtt.svg) - [cli.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/batch-l4s-s2-twoflow-ns-cubic-vs-prague-red_150000_-160ms.tcpdump_cli_cli.r.pcap.xz) - [srv.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/batch-l4s-s2-twoflow-ns-cubic-vs-prague-red_150000_-160ms.tcpdump_srv_srv.l.pcap.xz) - [teardown](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/batch-l4s-s2-twoflow-ns-cubic-vs-prague-red_150000_-160ms.teardown.log)
20ms | red(400000) | [plot](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/l4s-s2-twoflow-ns-cubic-vs-prague-red_400000_-20ms_tcp_delivery_with_rtt.svg) - [cli.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/batch-l4s-s2-twoflow-ns-cubic-vs-prague-red_400000_-20ms.tcpdump_cli_cli.r.pcap.xz) - [srv.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/batch-l4s-s2-twoflow-ns-cubic-vs-prague-red_400000_-20ms.tcpdump_srv_srv.l.pcap.xz) - [teardown](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/batch-l4s-s2-twoflow-ns-cubic-vs-prague-red_400000_-20ms.teardown.log)
80ms | red(400000) | [plot](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/l4s-s2-twoflow-ns-cubic-vs-prague-red_400000_-80ms_tcp_delivery_with_rtt.svg) - [cli.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/batch-l4s-s2-twoflow-ns-cubic-vs-prague-red_400000_-80ms.tcpdump_cli_cli.r.pcap.xz) - [srv.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/batch-l4s-s2-twoflow-ns-cubic-vs-prague-red_400000_-80ms.tcpdump_srv_srv.l.pcap.xz) - [teardown](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/batch-l4s-s2-twoflow-ns-cubic-vs-prague-red_400000_-80ms.teardown.log)
160ms | red(400000) | [plot](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/l4s-s2-twoflow-ns-cubic-vs-prague-red_400000_-160ms_tcp_delivery_with_rtt.svg) - [cli.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/batch-l4s-s2-twoflow-ns-cubic-vs-prague-red_400000_-160ms.tcpdump_cli_cli.r.pcap.xz) - [srv.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/batch-l4s-s2-twoflow-ns-cubic-vs-prague-red_400000_-160ms.tcpdump_srv_srv.l.pcap.xz) - [teardown](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s2-twoflow/batch-l4s-s2-twoflow-ns-cubic-vs-prague-red_400000_-160ms.teardown.log)

### Scenario 3: Bottleneck Shift

RTT | [SCE](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s3-bottleneck-shift/) | [L4S](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s3-bottleneck-shift/)
--- | ----------------------------------------------------------------------------------- | -----------------------------------------------------------------------------------
20ms | [plot](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s3-bottleneck-shift/sce-s3-bottleneck-shift-ns-cubic-sce-50Mbit-20ms_tcp_delivery_with_rtt.svg) - [cli.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s3-bottleneck-shift/batch-sce-s3-bottleneck-shift-ns-cubic-sce-50Mbit-20ms.tcpdump_cli_cli.r.pcap.xz) - [srv.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s3-bottleneck-shift/batch-sce-s3-bottleneck-shift-ns-cubic-sce-50Mbit-20ms.tcpdump_srv_srv.l.pcap.xz) - [teardown](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s3-bottleneck-shift/batch-sce-s3-bottleneck-shift-ns-cubic-sce-50Mbit-20ms.teardown.log) | [plot](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s3-bottleneck-shift/l4s-s3-bottleneck-shift-ns-prague-50Mbit-20ms_tcp_delivery_with_rtt.svg) - [cli.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s3-bottleneck-shift/batch-l4s-s3-bottleneck-shift-ns-prague-50Mbit-20ms.tcpdump_cli_cli.r.pcap.xz) - [srv.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s3-bottleneck-shift/batch-l4s-s3-bottleneck-shift-ns-prague-50Mbit-20ms.tcpdump_srv_srv.l.pcap.xz) - [teardown](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s3-bottleneck-shift/batch-l4s-s3-bottleneck-shift-ns-prague-50Mbit-20ms.teardown.log)
80ms | [plot](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s3-bottleneck-shift/sce-s3-bottleneck-shift-ns-cubic-sce-50Mbit-80ms_tcp_delivery_with_rtt.svg) - [cli.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s3-bottleneck-shift/batch-sce-s3-bottleneck-shift-ns-cubic-sce-50Mbit-80ms.tcpdump_cli_cli.r.pcap.xz) - [srv.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s3-bottleneck-shift/batch-sce-s3-bottleneck-shift-ns-cubic-sce-50Mbit-80ms.tcpdump_srv_srv.l.pcap.xz) - [teardown](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s3-bottleneck-shift/batch-sce-s3-bottleneck-shift-ns-cubic-sce-50Mbit-80ms.teardown.log) | [plot](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s3-bottleneck-shift/l4s-s3-bottleneck-shift-ns-prague-50Mbit-80ms_tcp_delivery_with_rtt.svg) - [cli.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s3-bottleneck-shift/batch-l4s-s3-bottleneck-shift-ns-prague-50Mbit-80ms.tcpdump_cli_cli.r.pcap.xz) - [srv.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s3-bottleneck-shift/batch-l4s-s3-bottleneck-shift-ns-prague-50Mbit-80ms.tcpdump_srv_srv.l.pcap.xz) - [teardown](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s3-bottleneck-shift/batch-l4s-s3-bottleneck-shift-ns-prague-50Mbit-80ms.teardown.log)

### Scenario 4: Capacity Reduction

Bandwidth1 | RTT | [SCE](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s4-capacity-reduction/) | [L4S](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s4-capacity-reduction/)
---------- | --- | ------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------
40Mbit | 20ms | [plot](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s4-capacity-reduction/sce-s4-capacity-reduction-ns-reno-sce-50Mbit-40mbit-20ms_tcp_delivery_with_rtt.svg) - [cli.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s4-capacity-reduction/batch-sce-s4-capacity-reduction-ns-reno-sce-50Mbit-40mbit-20ms.tcpdump_cli_cli.r.pcap.xz) - [srv.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s4-capacity-reduction/batch-sce-s4-capacity-reduction-ns-reno-sce-50Mbit-40mbit-20ms.tcpdump_srv_srv.l.pcap.xz) - [teardown](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s4-capacity-reduction/batch-sce-s4-capacity-reduction-ns-reno-sce-50Mbit-40mbit-20ms.teardown.log) | [plot](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s4-capacity-reduction/l4s-s4-capacity-reduction-ns-prague-50Mbit-40mbit-20ms_tcp_delivery_with_rtt.svg) - [cli.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s4-capacity-reduction/batch-l4s-s4-capacity-reduction-ns-prague-50Mbit-40mbit-20ms.tcpdump_cli_cli.r.pcap.xz) - [srv.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s4-capacity-reduction/batch-l4s-s4-capacity-reduction-ns-prague-50Mbit-40mbit-20ms.tcpdump_srv_srv.l.pcap.xz) - [teardown](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s4-capacity-reduction/batch-l4s-s4-capacity-reduction-ns-prague-50Mbit-40mbit-20ms.teardown.log)
40Mbit | 80ms | [plot](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s4-capacity-reduction/sce-s4-capacity-reduction-ns-reno-sce-50Mbit-40mbit-80ms_tcp_delivery_with_rtt.svg) - [cli.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s4-capacity-reduction/batch-sce-s4-capacity-reduction-ns-reno-sce-50Mbit-40mbit-80ms.tcpdump_cli_cli.r.pcap.xz) - [srv.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s4-capacity-reduction/batch-sce-s4-capacity-reduction-ns-reno-sce-50Mbit-40mbit-80ms.tcpdump_srv_srv.l.pcap.xz) - [teardown](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s4-capacity-reduction/batch-sce-s4-capacity-reduction-ns-reno-sce-50Mbit-40mbit-80ms.teardown.log) | [plot](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s4-capacity-reduction/l4s-s4-capacity-reduction-ns-prague-50Mbit-40mbit-80ms_tcp_delivery_with_rtt.svg) - [cli.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s4-capacity-reduction/batch-l4s-s4-capacity-reduction-ns-prague-50Mbit-40mbit-80ms.tcpdump_cli_cli.r.pcap.xz) - [srv.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s4-capacity-reduction/batch-l4s-s4-capacity-reduction-ns-prague-50Mbit-40mbit-80ms.tcpdump_srv_srv.l.pcap.xz) - [teardown](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s4-capacity-reduction/batch-l4s-s4-capacity-reduction-ns-prague-50Mbit-40mbit-80ms.teardown.log)
5Mbit | 20ms | [plot](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s4-capacity-reduction/sce-s4-capacity-reduction-ns-reno-sce-50Mbit-5mbit-20ms_tcp_delivery_with_rtt.svg) - [cli.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s4-capacity-reduction/batch-sce-s4-capacity-reduction-ns-reno-sce-50Mbit-5mbit-20ms.tcpdump_cli_cli.r.pcap.xz) - [srv.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s4-capacity-reduction/batch-sce-s4-capacity-reduction-ns-reno-sce-50Mbit-5mbit-20ms.tcpdump_srv_srv.l.pcap.xz) - [teardown](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s4-capacity-reduction/batch-sce-s4-capacity-reduction-ns-reno-sce-50Mbit-5mbit-20ms.teardown.log) | [plot](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s4-capacity-reduction/l4s-s4-capacity-reduction-ns-prague-50Mbit-5mbit-20ms_tcp_delivery_with_rtt.svg) - [cli.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s4-capacity-reduction/batch-l4s-s4-capacity-reduction-ns-prague-50Mbit-5mbit-20ms.tcpdump_cli_cli.r.pcap.xz) - [srv.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s4-capacity-reduction/batch-l4s-s4-capacity-reduction-ns-prague-50Mbit-5mbit-20ms.tcpdump_srv_srv.l.pcap.xz) - [teardown](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s4-capacity-reduction/batch-l4s-s4-capacity-reduction-ns-prague-50Mbit-5mbit-20ms.teardown.log)
5Mbit | 80ms | [plot](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s4-capacity-reduction/sce-s4-capacity-reduction-ns-reno-sce-50Mbit-5mbit-80ms_tcp_delivery_with_rtt.svg) - [cli.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s4-capacity-reduction/batch-sce-s4-capacity-reduction-ns-reno-sce-50Mbit-5mbit-80ms.tcpdump_cli_cli.r.pcap.xz) - [srv.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s4-capacity-reduction/batch-sce-s4-capacity-reduction-ns-reno-sce-50Mbit-5mbit-80ms.tcpdump_srv_srv.l.pcap.xz) - [teardown](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s4-capacity-reduction/batch-sce-s4-capacity-reduction-ns-reno-sce-50Mbit-5mbit-80ms.teardown.log) | [plot](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s4-capacity-reduction/l4s-s4-capacity-reduction-ns-prague-50Mbit-5mbit-80ms_tcp_delivery_with_rtt.svg) - [cli.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s4-capacity-reduction/batch-l4s-s4-capacity-reduction-ns-prague-50Mbit-5mbit-80ms.tcpdump_cli_cli.r.pcap.xz) - [srv.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s4-capacity-reduction/batch-l4s-s4-capacity-reduction-ns-prague-50Mbit-5mbit-80ms.tcpdump_srv_srv.l.pcap.xz) - [teardown](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s4-capacity-reduction/batch-l4s-s4-capacity-reduction-ns-prague-50Mbit-5mbit-80ms.teardown.log)

### Scenario 5: WiFi Burstiness

qdisc | RTT | [SCE](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s5-burstiness/)
----- | --- | -----------------------------------------------------------------------------
cake | 20ms | [plot](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s5-burstiness/sce-s5-burstiness-ns-cubic-sce-cake-50Mbit-20ms_tcp_delivery_with_rtt.svg) - [cli.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s5-burstiness/batch-sce-s5-burstiness-ns-cubic-sce-cake-50Mbit-20ms.tcpdump_cli_cli.r.pcap.xz) - [srv.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s5-burstiness/batch-sce-s5-burstiness-ns-cubic-sce-cake-50Mbit-20ms.tcpdump_srv_srv.l.pcap.xz) - [teardown](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s5-burstiness/batch-sce-s5-burstiness-ns-cubic-sce-cake-50Mbit-20ms.teardown.log)
cake | 80ms | [plot](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s5-burstiness/sce-s5-burstiness-ns-cubic-sce-cake-50Mbit-80ms_tcp_delivery_with_rtt.svg) - [cli.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s5-burstiness/batch-sce-s5-burstiness-ns-cubic-sce-cake-50Mbit-80ms.tcpdump_cli_cli.r.pcap.xz) - [srv.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s5-burstiness/batch-sce-s5-burstiness-ns-cubic-sce-cake-50Mbit-80ms.tcpdump_srv_srv.l.pcap.xz) - [teardown](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s5-burstiness/batch-sce-s5-burstiness-ns-cubic-sce-cake-50Mbit-80ms.teardown.log)
twin_codel_af | 20ms | [plot](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s5-burstiness/sce-s5-burstiness-ns-cubic-sce-twin_codel_af-50Mbit-20ms_tcp_delivery_with_rtt.svg) - [cli.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s5-burstiness/batch-sce-s5-burstiness-ns-cubic-sce-twin_codel_af-50Mbit-20ms.tcpdump_cli_cli.r.pcap.xz) - [srv.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s5-burstiness/batch-sce-s5-burstiness-ns-cubic-sce-twin_codel_af-50Mbit-20ms.tcpdump_srv_srv.l.pcap.xz) - [teardown](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s5-burstiness/batch-sce-s5-burstiness-ns-cubic-sce-twin_codel_af-50Mbit-20ms.teardown.log)
twin_codel_af | 80ms | [plot](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s5-burstiness/sce-s5-burstiness-ns-cubic-sce-twin_codel_af-50Mbit-80ms_tcp_delivery_with_rtt.svg) - [cli.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s5-burstiness/batch-sce-s5-burstiness-ns-cubic-sce-twin_codel_af-50Mbit-80ms.tcpdump_cli_cli.r.pcap.xz) - [srv.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s5-burstiness/batch-sce-s5-burstiness-ns-cubic-sce-twin_codel_af-50Mbit-80ms.tcpdump_srv_srv.l.pcap.xz) - [teardown](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s5-burstiness/batch-sce-s5-burstiness-ns-cubic-sce-twin_codel_af-50Mbit-80ms.teardown.log)

qdisc | RTT | [L4S](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s5-burstiness/)
----- | --- | -----------------------------------------------------------------------------
dualpi2 | 20ms | [plot](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s5-burstiness/l4s-s5-burstiness-ns-prague-dualpi2-50Mbit-20ms_tcp_delivery_with_rtt.svg) - [cli.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s5-burstiness/batch-l4s-s5-burstiness-ns-prague-dualpi2-50Mbit-20ms.tcpdump_cli_cli.r.pcap.xz) - [srv.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s5-burstiness/batch-l4s-s5-burstiness-ns-prague-dualpi2-50Mbit-20ms.tcpdump_srv_srv.l.pcap.xz) - [teardown](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s5-burstiness/batch-l4s-s5-burstiness-ns-prague-dualpi2-50Mbit-20ms.teardown.log)
dualpi2 | 80ms | [plot](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s5-burstiness/l4s-s5-burstiness-ns-prague-dualpi2-50Mbit-80ms_tcp_delivery_with_rtt.svg) - [cli.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s5-burstiness/batch-l4s-s5-burstiness-ns-prague-dualpi2-50Mbit-80ms.tcpdump_cli_cli.r.pcap.xz) - [srv.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s5-burstiness/batch-l4s-s5-burstiness-ns-prague-dualpi2-50Mbit-80ms.tcpdump_srv_srv.l.pcap.xz) - [teardown](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s5-burstiness/batch-l4s-s5-burstiness-ns-prague-dualpi2-50Mbit-80ms.teardown.log)

### Scenario 6: Jitter

_Note:_ netem jitter params are: total added delay, jitter and correlation

netem-jitter-params | RTT | [SCE](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s6-jitter/) | [L4S](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s6-jitter/)
------------------- | --- | ------------------------------------------------------------------------- | -------------------------------------------------------------------------
2ms 1ms 10% | 80ms | [plot](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s6-jitter/sce-s6-jitter-ns-cubic-sce-twin_codel_af-50Mbit-80ms-netem_delay_2ms_1ms_10__tcp_delivery_with_rtt.svg) - [cli.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s6-jitter/batch-sce-s6-jitter-ns-cubic-sce-twin_codel_af-50Mbit-80ms-netem_delay_2ms_1ms_10_.tcpdump_cli_cli.r.pcap.xz) - [srv.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s6-jitter/batch-sce-s6-jitter-ns-cubic-sce-twin_codel_af-50Mbit-80ms-netem_delay_2ms_1ms_10_.tcpdump_srv_srv.l.pcap.xz) - [teardown](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s6-jitter/batch-sce-s6-jitter-ns-cubic-sce-twin_codel_af-50Mbit-80ms-netem_delay_2ms_1ms_10_.teardown.log) | [plot](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s6-jitter/l4s-s6-jitter-ns-prague-dualpi2-50Mbit-80ms-netem_delay_2ms_1ms_10__tcp_delivery_with_rtt.svg) - [cli.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s6-jitter/batch-l4s-s6-jitter-ns-prague-dualpi2-50Mbit-80ms-netem_delay_2ms_1ms_10_.tcpdump_cli_cli.r.pcap.xz) - [srv.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s6-jitter/batch-l4s-s6-jitter-ns-prague-dualpi2-50Mbit-80ms-netem_delay_2ms_1ms_10_.tcpdump_srv_srv.l.pcap.xz) - [teardown](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s6-jitter/batch-l4s-s6-jitter-ns-prague-dualpi2-50Mbit-80ms-netem_delay_2ms_1ms_10_.teardown.log)
4ms 2ms 10% | 80ms | [plot](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s6-jitter/sce-s6-jitter-ns-cubic-sce-twin_codel_af-50Mbit-80ms-netem_delay_4ms_2ms_10__tcp_delivery_with_rtt.svg) - [cli.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s6-jitter/batch-sce-s6-jitter-ns-cubic-sce-twin_codel_af-50Mbit-80ms-netem_delay_4ms_2ms_10_.tcpdump_cli_cli.r.pcap.xz) - [srv.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s6-jitter/batch-sce-s6-jitter-ns-cubic-sce-twin_codel_af-50Mbit-80ms-netem_delay_4ms_2ms_10_.tcpdump_srv_srv.l.pcap.xz) - [teardown](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s6-jitter/batch-sce-s6-jitter-ns-cubic-sce-twin_codel_af-50Mbit-80ms-netem_delay_4ms_2ms_10_.teardown.log) | [plot](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s6-jitter/l4s-s6-jitter-ns-prague-dualpi2-50Mbit-80ms-netem_delay_4ms_2ms_10__tcp_delivery_with_rtt.svg) - [cli.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s6-jitter/batch-l4s-s6-jitter-ns-prague-dualpi2-50Mbit-80ms-netem_delay_4ms_2ms_10_.tcpdump_cli_cli.r.pcap.xz) - [srv.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s6-jitter/batch-l4s-s6-jitter-ns-prague-dualpi2-50Mbit-80ms-netem_delay_4ms_2ms_10_.tcpdump_srv_srv.l.pcap.xz) - [teardown](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s6-jitter/batch-l4s-s6-jitter-ns-prague-dualpi2-50Mbit-80ms-netem_delay_4ms_2ms_10_.teardown.log)
10ms 5ms 10% | 80ms | [plot](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s6-jitter/sce-s6-jitter-ns-cubic-sce-twin_codel_af-50Mbit-80ms-netem_delay_10ms_5ms_10__tcp_delivery_with_rtt.svg) - [cli.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s6-jitter/batch-sce-s6-jitter-ns-cubic-sce-twin_codel_af-50Mbit-80ms-netem_delay_10ms_5ms_10_.tcpdump_cli_cli.r.pcap.xz) - [srv.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s6-jitter/batch-sce-s6-jitter-ns-cubic-sce-twin_codel_af-50Mbit-80ms-netem_delay_10ms_5ms_10_.tcpdump_srv_srv.l.pcap.xz) - [teardown](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/sce-s6-jitter/batch-sce-s6-jitter-ns-cubic-sce-twin_codel_af-50Mbit-80ms-netem_delay_10ms_5ms_10_.teardown.log) | [plot](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s6-jitter/l4s-s6-jitter-ns-prague-dualpi2-50Mbit-80ms-netem_delay_10ms_5ms_10__tcp_delivery_with_rtt.svg) - [cli.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s6-jitter/batch-l4s-s6-jitter-ns-prague-dualpi2-50Mbit-80ms-netem_delay_10ms_5ms_10_.tcpdump_cli_cli.r.pcap.xz) - [srv.pcap](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s6-jitter/batch-l4s-s6-jitter-ns-prague-dualpi2-50Mbit-80ms-netem_delay_10ms_5ms_10_.tcpdump_srv_srv.l.pcap.xz) - [teardown](http://sce.dnsmgr.net/results/ect1-2020-04-23-final/l4s-s6-jitter/batch-l4s-s6-jitter-ns-prague-dualpi2-50Mbit-80ms-netem_delay_10ms_5ms_10_.teardown.log)

## Appendix

### Background

Conventional congestion control is based on the
[AIMD](https://en.wikipedia.org/wiki/Additive_increase/multiplicative_decrease)
(Additive Increase, Multiplicate Decrease) principle.  This exhibits a
characteristic sawtooth pattern in which the congestion window grows slowly,
then reduces rapidly on receipt of a congestion signal.  This was introduced to
solve the problem of congestion collapse.  However, it is incapable of finding
and settling on the ideal congestion window, which is approximately equal to the
bandwidth-delay product (BDP) plus a jitter margin.

High Fidelity Congestion Control is an attempt to solve this problem by
implementing a finer-grained control loop between the network and the transport
layer.  Hence, instead of oscillating around the ideal (at best), the transport
can keep the ideal amount of traffic in the network, simultaneously maximising
throughput and minimising latency.

### Typical Internet Jitter

The following two [IRTT](https://github.com/heistp/irtt) results illustrate
typical jitter on paths on the open Internet.

The first is to a regional server about 50km away, where mean IPDV (jitter) is
2.09ms, already enough to trigger a _false positive_ in the L4S classic queue
detection heuristic:

```
[Connecting] connecting to redacted.drhleny.cz
[185.xxx.xxx.xxx:2112] [Connected] connection established
[185.xxx.xxx.xxx:2112] [WaitForPackets] waiting 116.3ms for final packets

                         Min     Mean   Median      Max  Stddev
                         ---     ----   ------      ---  ------
                RTT  13.26ms   17.2ms   16.6ms  38.77ms  2.29ms
         send delay   8.88ms  11.72ms  11.29ms  31.56ms  1.66ms
      receive delay   3.63ms   5.49ms   5.28ms  23.23ms  1.48ms
                                                               
      IPDV (jitter)    463ns   2.09ms   1.46ms  20.83ms  2.32ms
          send IPDV    626ns   1.48ms    970µs  18.26ms  1.74ms
       receive IPDV    434ns   1.23ms    814µs  18.23ms  1.63ms
                                                               
     send call time   27.9µs    129µs             286µs  44.2µs
        timer error    229ns   1.48ms            3.51ms   704µs
  server proc. time   43.6µs   81.8µs             282µs  12.1µs

                duration: 1m0s (wait 116.3ms)
   packets sent/received: 2998/2992 (0.20% loss)
 server packets received: 2993/2998 (0.17%/0.03% loss up/down)
     bytes sent/received: 479680/478720
       send/receive rate: 64.0 Kbps / 63.9 Kbps
           packet length: 160 bytes
             timer stats: 1/2999 (0.03%) missed, 7.39% error
```

The second is a transcontinental path from the Czech Republic to the
US West Coast, where mean jitter is observed to be 13.42ms:

```
[Connecting] connecting to redacted.portland.usa
[65.xxx.xxx.xxx:2112] [Connected] connection established
[65.xxx.xxx.xxx:2112] [WaitForPackets] waiting 1.03s for final packets

                         Min     Mean   Median      Max   Stddev
                         ---     ----   ------      ---   ------
                RTT  159.7ms  179.6ms  175.8ms    344ms  20.45ms
         send delay  63.53ms  74.53ms  67.59ms  164.4ms  15.25ms
      receive delay  95.06ms  105.1ms  99.32ms  199.4ms  13.64ms
                                                                
      IPDV (jitter)   4.32µs  13.42ms  11.67ms    151ms  13.65ms
          send IPDV    934ns   9.63ms   2.98ms  89.41ms  12.89ms
       receive IPDV     14ns   8.38ms   3.87ms  102.7ms  13.23ms
                                                                
     send call time   31.6µs    137µs             291µs   44.5µs
        timer error    2.8µs   1.31ms               4ms    744µs
  server proc. time   2.59µs   5.61µs            81.4µs   3.14µs

                duration: 1m1s (wait 1.03s)
   packets sent/received: 2996/2995 (0.03% loss)
 server packets received: 2996/2996 (0.00%/0.03% loss up/down)
     bytes sent/received: 479360/479200
       send/receive rate: 63.9 Kbps / 63.9 Kbps
           packet length: 160 bytes
             timer stats: 4/3000 (0.13%) missed, 6.53% error
```

### Test Setup

The test setup consists of a dumbbell configuration (client, middlebox and
server) for both SCE and L4S. For these tests, all results were produced on a
single physical machine for each using network namespaces.
[Flent](https://flent.org/) was used for all tests.

For SCE, commit
chromi/sce@0eddf2ad978eaaa4a7f0403e6345001ad66d3233
(from Mar 9, 2020) was used.

For L4S, commit
L4STeam/linux@e741f5ac756503e27be9c183dd107eadbea40c5c
(from Apr 8, 2020) was used.

The single **fl** script performs the following functions:
- updates itself onto the management server and clients
- runs tests (./fl run), plot results (./fl plot) and pushes them to a server
- acts as a harness for flent, setting up and tearing down the test config
- generates this README.md from a template

If there are more questions, feel free to file an
[issue](https://github.com/heistp/sce-l4s-ect1/issues).

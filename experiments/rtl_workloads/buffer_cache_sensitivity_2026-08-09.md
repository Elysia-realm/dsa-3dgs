# Write-buffer and state-cache sensitivity

Date: 2026-08-09. All data is local to `D:\3DGS`.

## Write buffer depth

For bonsai/garden/train n8 workloads, depths 2/4/8/16 produced identical cycles, stalls, transaction counts and frame-state hashes under both ideal and limited AXI profiles. Under an additional train n8 stress profile with 64-cycle B response, all depths completed in 13510 cycles. Deeper buffers shifted cycles between output backpressure and same-pixel hazard waiting but did not improve completion time.

Storage payload is 152 bits per queued entry, excluding FIFO control and tag-CAM comparison logic:

| Depth | Payload bits | Relative to depth 2 |
|---:|---:|---:|
| 2 | 304 | 1× |
| 4 | 608 | 2× |
| 8 | 1216 | 4× |
| 16 | 2432 | 8× |

Decision: use depth 2 as the default process-independent RTL baseline. Keep the parameter for later PPA sweeps.

## Safe adjacent write combining opportunity

The three n8 workloads report zero consecutive same-pixel commits in both AXI profiles. Therefore an adjacent-only coalescer would remove zero writes. Arbitrary queue search/reordering would add CAM and ordering complexity and is not implemented without a representative benefit signal.

## State cache capacity

Train n32 at 64×36 provides more reuse than the n8 workloads:

| Entries | Profile | Cycles | Misses / 795 commits | Miss rate | Frame hash |
|---:|---|---:|---:|---:|---|
| 32 | ideal | 7448 | 793 | 99.75% | identical |
| 128 | ideal | 7329 | 768 | 96.60% | identical |
| 512 | ideal | 6582 | 583 | 73.33% | identical |
| 32 | limited | 14155 | 793 | 99.75% | identical |
| 128 | limited | 13906 | 768 | 96.60% | identical |
| 512 | limited | 12415 | 583 | 73.33% | identical |

At 512 entries, cycles improve by 1.13× ideal and 1.14× limited relative to 32 entries, while AXI state reads decrease by 26.5%. The default system cache remains 4096 entries; this experiment confirms that capacity is useful once the workload has pixel reuse, but it does not yet select the final ASIC capacity because SRAM area and full-scene traces are still required.

## Next performance target

The 512-entry run exposes output FIFO backpressure as cache hits remove read latency: 184 ideal and 1074 limited output-stall cycles. The next justified optimization is write-side throughput reduction or overlap under larger representative workloads, not further FIFO depth alone.

Software writes DESC_ADDR and CTRL, then polls STATUS. The first descriptor copies one beat and
chains to a second, which polls a word until it reads 1 before its beat; a write after the job is
outside any:

  $ coralview dma --platform dma-sub.json --beats 2 dma.vcd
  job 1: started 3 by pc 00000104, descriptor 20006000
    descriptor 20006000 fetched 5-8: 20004000 -> 00010040, 4 bytes in 4-byte beats, next 20006020
    descriptor 20006020 fetched 14-17: 20004010 -> 00010050, 4 bytes in 4-byte beats, polls 20000100 & 000000ff = 00000001
    beats 2, cycles 9-25, one every 13.0 cycles: latency, request accepted to response, min/mean/max reads 1/1.0/1, writes 1/1.5/2; 0.471 bytes/cycle, 2 polls
             9 read 20004000 4 bytes, response 10; write 00010040 accepted 11, response 13
            22 read 20004010 4 bytes, response 23; write 00010050 accepted 24, response 25
    finished 25: 8 bytes, 23 cycles from start, 0.348 bytes/cycle
    software saw done at 27 by pc 0000010c, 24 cycles after the start, 2 STATUS reads
        29 stray: host write 00010060 with no job
  root TOP.sub: jobs 1, 8 bytes in 32 cycles, host port at most 1 outstanding, 1 stray

With the host port misnamed the description does not match the trace:

  $ sed s/io_tl_host_/io_tl_hst_/ dma-sub.json > renamed.json
  $ coralview dma --platform renamed.json dma.vcd 2>&1 | head -3
  platform dma-sub does not match the trace (model dma):
    missing io_tl_hst_a_valid

As JSON lines, each job once it is done with, its beats as transactions, then the summary:

  $ coralview dma --platform dma-sub.json --format jsonl dma.vcd | jq -c 'select(.type == "dma.job") | [.span, .pc, [.descriptors[] | [.src.address, .dst.address, .len]], (.beats | length), .observed]'
  [{"start":3,"stop":25},260,[[536887296,65600,4],[536887312,65616,4]],2,{"cycle":27,"pc":268}]
  $ coralview dma --platform dma-sub.json --format jsonl dma.vcd | jq -c 'select(.type != "dma.job")'
  {"type":"coralview","schema_version":1,"model":"dma","platform":"dma-sub","trace":"dma.vcd"}
  {"type":"dma.stray","cycle":29,"what":"host write 00010060 with no job"}
  {"type":"dma.summary","cycles":32,"jobs":1,"bytes":8,"max_outstanding":1,"stray":1}

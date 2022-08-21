#!/bin/bash
p4c-dpdk main.p4 \
    -o main.spec \
    --arch psa \
    --bf-rt-schema main.bfrt.json \
    --context context.json \
    --p4runtime-files main.pb.txt \
    --p4runtime-format text

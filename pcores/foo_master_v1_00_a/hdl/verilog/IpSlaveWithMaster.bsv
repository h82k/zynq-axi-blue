
// Copyright (c) 2012 Nokia, Inc.

// Permission is hereby granted, free of charge, to any person
// obtaining a copy of this software and associated documentation
// files (the "Software"), to deal in the Software without
// restriction, including without limitation the rights to use, copy,
// modify, merge, publish, distribute, sublicense, and/or sell copies
// of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:

// The above copyright notice and this permission notice shall be
// included in all copies or substantial portions of the Software.

// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
// EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
// NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
// BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
// ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
// CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import RegFile::*;
import Adapter::*;
import AxiMasterSlave::*;
import FifoToAxi::*;
import FooWrapper::*;
import GetPut::*;
import Connectable::*;
import Clocks::*;

interface IpSlave;
   method Action put(Bit#(12) addr, Bit#(32) v);
   method ActionValue#(Bit#(32)) get(Bit#(12) addr);
endinterface

interface IpSlaveWithMaster;
   method Bit#(1) error();
   method Bit#(1) interrupt();
   interface IpSlave ctrl;
   interface IpSlave fifo;
   interface AxiMasterWrite#(64,8) axi0w;
   interface AxiMasterRead#(64) axi0r;
   interface AxiMasterWrite#(64,8) axi1w;
   interface AxiMasterRead#(64) axi1r;
   interface AxiMasterWrite#(64,8) axi2w;
   interface AxiMasterRead#(64) axi2r;
endinterface

module mkIpSlaveWithMaster#(Clock axi_clk)(IpSlaveWithMaster);

   FromBit32#(FooRequest) requestFifo <- mkFromBit32();
   ToBit32#(FooResponse) responseFifo <- mkToBit32();
   FooWrapper fooWrapper <- mkFooWrapper(axi_clk, requestFifo, responseFifo);

   RegFile#(Bit#(12), Bit#(32)) rf <- mkRegFile(0, 12'h00f);
   Reg#(Bool) interrupted <- mkReg(False);
   Reg#(Bool) interruptCleared <- mkReg(False);
   Reg#(Bit#(32)) getWordCount <- mkReg(0);
   Reg#(Bit#(32)) putWordCount <- mkReg(0);
   Reg#(Bit#(32)) word0Put  <- mkReg(0);
   Reg#(Bit#(32)) word1Put  <- mkReg(0);
   Reg#(Bit#(32)) underflowCount <- mkReg(0);
   Reg#(Bit#(32)) overflowCount <- mkReg(0);

   rule interrupted_rule;
       interrupted <= responseFifo.notEmpty;
   endrule
   rule reset_interrupt_cleared_rule if (!interrupted);
       interruptCleared <= False;
   endrule

   interface IpSlave ctrl;
       method Action put(Bit#(12) addr, Bit#(32) v);
           if (addr == 12'h000 && v[0] == 1'b1 && interrupted)
           begin
               interruptCleared <= True;
           end
           rf.upd(addr, v);
       endmethod

       method ActionValue#(Bit#(32)) get(Bit#(12) addr);
           let v = rf.sub(addr);
           if (addr == 12'h000)
           begin
               v[0] = interrupted ? 1'd1 : 1'd0 ;
               v[16] = responseFifo.notFull ? 1'd1 : 1'd0;
           end
           if (addr == 12'h004)
               v = 32'h02142011;
           if (addr == 12'h008)
               v = fooWrapper.requestSize;
           if (addr == 12'h00C)
               v = fooWrapper.responseSize;
           if (addr == 12'h010)
               v = fooWrapper.reqCount;
           if (addr == 12'h014)
               v = fooWrapper.respCount;
           if (addr == 12'h018)
               v = underflowCount;
           if (addr == 12'h01C)
               v = overflowCount;
           if (addr == 12'h020)
               v = (32'h68470000
                    | (responseFifo.notFull ? 32'h20 : 0) | (responseFifo.notEmpty ? 32'h10 : 0)
                    | (requestFifo.notFull ? 32'h02 : 0) | (requestFifo.notEmpty ? 32'h01 : 0));
           if (addr == 12'h024)
               v = putWordCount;
           if (addr == 12'h028)
               v = getWordCount;
           if (addr == 12'h02C)
               v = word0Put;
           if (addr == 12'h030)
               v = word1Put;
           if (addr == 12'h034)
               v = fooWrapper.junkReqCount;
           if (addr == 12'h038)
               v = fooWrapper.blockedRequestsDiscardedCount;
           if (addr == 12'h03C)
               v = fooWrapper.blockedResponsesDiscardedCount;
           return v;
       endmethod
   endinterface

   interface IpSlave fifo;
       method Action put(Bit#(12) addr, Bit#(32) v);
           word0Put <= word1Put;
           word1Put <= v;
           if (requestFifo.notFull)
           begin
               putWordCount <= putWordCount + 1;
               requestFifo.enq(v);
           end
           else
           begin
               overflowCount <= overflowCount + 1;
           end
       endmethod

       method ActionValue#(Bit#(32)) get(Bit#(12) addr);
           let v = 32'h050a050a;
           if (responseFifo.notEmpty)
           begin
               let r = responseFifo.first(); 
               if (r matches tagged Valid .b) begin
                   v = b;
                   responseFifo.deq;
                   getWordCount <= getWordCount + 1;
               end
           end
           else
           begin
               underflowCount <= underflowCount + 1;
           end
           return v;
       endmethod
   endinterface

   method Bit#(1) error();
       return 0;
   endmethod

   method Bit#(1) interrupt();
       if (rf.sub(12'h04)[0] == 1'd1 && !interruptCleared)
           return interrupted ? 1'd1 : 1'd0;
       else
           return 1'd0;
   endmethod

   interface AxiMasterWrite axi0w = fooWrapper.axi0w;
   interface AxiMasterWrite axi0r = fooWrapper.axi0r;
   interface AxiMasterWrite axi1w = fooWrapper.axi1w;
   interface AxiMasterWrite axi1r = fooWrapper.axi1r;
   interface AxiMasterWrite axi2w = fooWrapper.axi2w;
   interface AxiMasterWrite axi2r = fooWrapper.axi2r;
endmodule

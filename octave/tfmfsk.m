% tfsk.m
% Author: Brady O'Brien 8 February 2016



%  Copyright 2016 David Rowe
%  
%  All rights reserved.
%
%  This program is free software; you can redistribute it and/or modify
%  it under the terms of the GNU Lesser General Public License version 2, as
%  published by the Free Software Foundation.  This program is
%  distributed in the hope that it will be useful, but WITHOUT ANY
%  WARRANTY; without even the implied warranty of MERCHANTABILITY or
%  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public
%  License for more details.
%
%  You should have received a copy of the GNU Lesser General Public License
%  along with this program; if not, see <http://www.gnu.org/licenses/>.


% Octave script to check c port of  mancyfsk/fmfsk against the fmfsk.m
%
#{

  FMFSK Modem automated test instructions:

  1. Use cmake to build in debug mode to ensure unittest/tfsk is built:

     $ cd ~/codec2
     $ rm -Rf build_linux && mkdir build_linux
     $ cd build_linux
     $ cmake -DCMAKE_BUILD_TYPE=Debug ..
     $ make

  2 - Change tfsk_location below if required
  3 - Ensure Octave packages signal and parallel are installed
  4 - Start Octave and run tfsk.m. It will perform all tests automatically

#}

%tfsk executable path/file
global tfsk_location = '../build_linux/unittest/tfmfsk';



fmfsk
pkg load signal;
pkg load parallel;
graphics_toolkit('gnuplot');


global mod_pass_fail_maxdiff = 1e-3/5000;

function mod = fmfsk_mod_c(Fs,Rs,bits)
    global tfsk_location;
    %command to be run by system to launch the modulator
    command = sprintf('%s M %d %d fsk_mod_ut_bitvec fsk_mod_ut_modvec fmfsk_mod_ut_log.txt',tfsk_location,Fs,Rs);
    %save input bits into a file
    bitvecfile = fopen('fsk_mod_ut_bitvec','wb+');
    fwrite(bitvecfile,bits,'uint8');
    fclose(bitvecfile);
    
    %run the modulator
    system(command);
    
    modvecfile = fopen('fsk_mod_ut_modvec','rb');
    mod = fread(modvecfile,'single');
    fclose(modvecfile);
    
endfunction


%Compare 2 vectors, fail if they are not close enough
function pass = vcompare(vc,voct,vname,tname,tol,pnum)
    
    %Get delta of vectors
    dvec = abs(abs(vc)-abs(voct));     
    
    %Normalize difference
    dvec = dvec ./ abs(max(abs(voct))+1e-8);
    
    maxdvec = abs(max(dvec));
    pass = maxdvec<tol;
    
    printf('  Comparing vectors %s in test %s. Diff is %f\n',vname,tname,maxdvec);
    
    if pass == 0
        printf('\n*** vcompare failed %s in test %s. Diff: %f Tol: %f\n\n',vname,tname,maxdvec,tol);
        
        titlestr = sprintf('Diff between C and Octave of %s for %s',vname,tname)
        figure(10+pnum*2)
        plot(abs(dvec))
        title(titlestr)
        
        figure(11+pnum*2)
        plot((1:length(vc)),abs(vc),(1:length(voct)),abs(voct))
    
    end
    
endfunction

function test_stats = fmfsk_demod_xt(Fs,Rs,mod,tname,M=2)
    global tfsk_location;
    
    size(mod)
    
    %Name of executable containing the modulator
    modvecfilename = sprintf('fmfsk_demod_ut_modvec_%d',getpid());
    bitvecfilename = sprintf('fmfsk_demod_ut_bitvec_%d',getpid());
    tvecfilename = sprintf('fmfsk_demod_ut_tracevec_%d.txt',getpid());
    
    delete(bitvecfilename);
    delete(modvecfilename);
    delete(tvecfilename);
    
    %command to be run by system to launch the demod
    command = sprintf('%s D %d %d %s %s %s',tfsk_location,Fs,Rs,modvecfilename,bitvecfilename,tvecfilename)
    
    %save modulated input into a file
    modvecfile = fopen(modvecfilename,'wb+');
    fwrite(modvecfile,mod,'single');
    fclose(modvecfile);
    
    %run the modulator
    system(command);
    
    bitvecfile = fopen(bitvecfilename,'rb');
    bits = fread(bitvecfile,'uint8');
    fclose(bitvecfile);
    bits = bits!=0;
    
    %Load test vec dump
    load(tvecfilename);
    
    %Clean up files
    delete(bitvecfilename);
    delete(modvecfilename);
    %delete(tvecfilename);
    
    o_norm_rx_timing = [];
    o_symsamp = [];
    o_rx_filt = [];
    
    %Run octave demod, dump some test vectors
    states = fmfsk_init(Fs,Rs);
    Ts = states.Ts;
    modin = mod;
    obits = [];
    while length(modin)>=states.nin
        ninold = states.nin;
        [bitbuf,states] = fmfsk_demod(states, modin(1:states.nin));
        modin=modin(ninold+1:length(modin));
        obits = [obits bitbuf];
        
        o_norm_rx_timing = [o_norm_rx_timing states.norm_rx_timing];
        o_symsamp = [o_symsamp states.symsamp];
        o_rx_filt = [o_rx_filt states.rx_filt];

    end
    
    close all
    
    % One part-per-thousand allowed on important parameters
    pass = 1;
    
    figure(8)
    plot((1:length(t_rx_filt)),t_rx_filt,(1:length(o_rx_filt)),o_rx_filt);
        figure(9)
    plot((1:length(t_symsamp)),t_symsamp,(1:length(o_symsamp)),o_symsamp);
    
    %vcompare(t_rx_filt,o_rx_filt,.001,8);
    vcompare(t_norm_rx_timing,o_norm_rx_timing,'norm rx timing',.001,9);
    vcompare(t_symsamp,o_symsamp,'symsamp',.001,10);
    
    assert(pass);
    diffpass = sum(xor(obits,bits'))<4;
    diffbits = sum(xor(obits,bits'));
    
    
    
    if diffpass==0
        printf('\n***bitcompare test failed test %s diff %d\n\n',tname,sum(xor(obits,bits')))
        figure(15)
        plot(xor(obits,bits'))
        title(sprintf('Bitcompare failure test %s',tname))
    end
    
    pass = pass && diffpass;
    
    
    test_stats.pass = pass;
    test_stats.diff = sum(xor(obits,bits'));
    test_stats.cbits = bits';
    test_stats.obits = obits;
    
endfunction

function [dmod,cmod,omod,pass] = fmfsk_mod_test(Fs,Rs,bits,tname,M=2)
    global mod_pass_fail_maxdiff;
    %Run the C modulator
    cmod = fmfsk_mod_c(Fs,Rs,bits);
    %Set up and run the octave modulator
    states.M = M;
    states = fmfsk_init(Fs,Rs);

    
    omod = fmfsk_mod(states,bits)';
    
    dmod = cmod-omod;
    pass = max(dmod)<(mod_pass_fail_maxdiff*length(dmod));
    if !pass
        printf('Mod failed test %s!\n',tname);
    end
endfunction

% Random bit modulator test
% Pass random bits through the modulators and compare
function pass = test_mod_fdvbcfg_randbits
    rand('state',1); 
    randn('state',1);
    bits = rand(1,19200)>.5;
    [dmod,cmod,omod,pass] = fmfsk_mod_test(48000,2400,bits,"mod fdvbcfg randbits");
    
    if(!pass)
        figure(1)
        plot(dmod)
        title("Difference between octave and C mod impl");
    end
    
endfunction

% run_sim copypasted from fsk_horus.m
% simulation of tx and rx side, add noise, channel impairments ----------------------

function stats = tfmfsk_run_sim(EbNodB,timing_offset=0,de=0,of=0,hpf=0,M=2)
  test_frame_mode = 2;
  frames = 70;
  %EbNodB = 3;
  %timing_offset = 0.0; % see resample() for clock offset below
  %fading = 0;          % modulates tx power at 2Hz with 20dB fade depth, 
                       % to simulate balloon rotating at end of mission
  df     = 0;          % tx tone freq drift in Hz/s
  dA     = 1;          % amplitude imbalance of tones (note this affects Eb so not a gd idea)

  more off
  rand('state',1); 
  randn('state',1);
  
  Fs = 48000;
  Rbit = 2400;

  % ----------------------------------------------------------------------

  fm_states.pre_emp = 0;
  fm_states.de_emp  = de;
  fm_states.Ts      = Fs/(Rbit*2);
  fm_states.Fs      = Fs; 
  fm_states.fc      = Fs/4; 
  fm_states.fm_max  = 3E3;
  fm_states.fd      = 5E3;
  fm_states.output_filter = of;
  fm_states = analog_fm_init(fm_states);

  % ----------------------------------------------------------------------
  
  states = fmfsk_init(Fs,Rbit);

  states.verbose = 0x1;
  Rs = states.Rs;
  nsym = states.nsym;
  Fs = states.Fs;
  nbit = states.nbit;

  EbNo = 10^(EbNodB/10);
  variance = states.Fs/(states.Rb*EbNo);

  % set up tx signal with payload bits based on test mode

  if test_frame_mode == 1
     % test frame of bits, which we repeat for convenience when BER testing
    test_frame = round(rand(1, states.nbit));
    tx_bits = [];
    for i=1:frames+1
      tx_bits = [tx_bits test_frame];
    end
  end
  if test_frame_mode == 2
    % random bits, just to make sure sync algs work on random data
    tx_bits = round(rand(1, states.nbit*(frames+1)));
  end
  if test_frame_mode == 3
    % repeating sequence of all symbols
    % great for initial test of demod if nothing else works, 
    % look for this pattern in rx_bits

       % ...10101...
      tx_bits = zeros(1, states.nbit*(frames+1));
      tx_bits(1:2:length(tx_bits)) = 1;

  end

  [b, a] = cheby1(4, 1, 300/Fs, 'high');   % 300Hz HPF to simulate FM radios
  
  tx_pmod = fmfsk_mod(states, tx_bits);
  figure(10)
  plot(tx_pmod);
  tx = analog_fm_mod(fm_states, tx_pmod);
  
  tx = tx(10:length(tx));
  if(timing_offset>0)
    tx = resample(tx, 1000, 1001); % simulated 1000ppm sample clock offset
  end
  

  noise = sqrt(variance)*randn(length(tx),1);
  rx    = tx + noise';
  
  %Demod by analog fm
  rx    = analog_fm_demod(fm_states, rx);
  
  %High-pass filter to simulate the FM radios
  if hpf>0
    printf("high-pass filtering!\n")
    rx = filter(b,a,rx);
  end
  %rx = real(rx);
  %b1 = fir2(100, [0 4000 5200 48000]/48000, [1 1 0.5 0.5]);
  %rx = filter(b1,1,rx);
  %[b a] = cheby2(6,40,[3000 6000]/(Fs/2));
  %rx = filter(b,a,rx);
  %rx = sign(rx);
  %rx(find (rx > 1)) = 1;
  %rx(find (rx < -1)) = -1;

  % dump simulated rx file

  timing_offset_samples = round(timing_offset*states.Ts);
  st = 1 + timing_offset_samples;
  rx_bits_buf = zeros(1,2*nbit);
  x_log = [];
  timing_nl_log = [];
  norm_rx_timing_log = [];
  f_int_resample_log = [];
  f_log = [];
  EbNodB_log = [];
  rx_bits_log = [];
  rx_bits_sd_log = [];


  test_name = sprintf("tfmfsk run sim EbNodB:%d frames:%d timing_offset:%d df:%d",EbNodB,frames,timing_offset,df);
  tstats = fmfsk_demod_xt(Fs,Rbit,rx',test_name,M); 

  pass = tstats.pass;
  obits = tstats.obits;
  cbits = tstats.cbits;
  
  % Figure out BER of octave and C modems
  bitcnt = length(tx_bits);
  rx_bits = obits;
  ber = 1;
  ox = 1;
  for offset = (1:100)
    nerr = sum(xor(rx_bits(offset:length(rx_bits)),tx_bits(1:length(rx_bits)+1-offset)));
    bern = nerr/(bitcnt-offset);
    if(bern < ber)
      ox = offset;
      best_nerr = nerr;
    end
    ber = min([ber bern]);
  end
  offset = ox;
  bero = ber;
  ber = 1;
  rx_bits = cbits;
  ox = 1;
  for offset = (1:100)
    nerr = sum(xor(rx_bits(offset:length(rx_bits)),tx_bits(1:length(rx_bits)+1-offset)));
    bern = nerr/(bitcnt-offset);
    if(bern < ber)
      ox = offset;
      best_nerr = nerr;
    end
    ber = min([ber bern]);
  end
  offset = ox;
  berc = ber;
  stats.berc = berc;
  stats.bero = bero;
  
    % non-coherent BER theory calculation
  % It was complicated, so I broke it up

  ms = 2;
  ns = (1:ms-1);
  as = (-1).^(ns+1);
  bs = (as./(ns+1));
  
  cs = ((ms-1)./ns);

  ds = ns.*log2(ms);
  es = ns+1;
  fs = exp( -(ds./es)*EbNo );
  
  thrncoh = ((ms/2)/(ms-1)) * sum(bs.*((ms-1)./ns).*exp( -(ds./es)*EbNo ));
  
  stats.thrncoh = thrncoh;
  stats.pass = pass;
 endfunction


function pass = ebno_battery_test(timing_offset,fading,df,dA,M)
    %Range of EbNodB over which to test
    ebnodbrange = (3:2:13);
    ebnodbs = length(ebnodbrange);
    
    mode = 2;
    %Replication of other parameters for parcellfun
    modev   = repmat(mode,1,ebnodbs);
    timingv = repmat(timing_offset,1,ebnodbs);
    fadingv = repmat(fading,1,ebnodbs);
    dfv     = repmat(df,1,ebnodbs);
    dav     = repmat(dA,1,ebnodbs);
    mv      = repmat(M,1,ebnodbs);
    statv = pararrayfun(floor(1.25*nproc()),@tfsk_run_sim,modev,ebnodbrange,timingv,fadingv,dfv,dav,mv);
    %statv = arrayfun(@tfsk_run_sim,modev,ebnodbrange,timingv,fadingv,dfv,dav,mv);

    passv = zeros(1,length(statv));
    for ii=(1:length(statv))
        passv(ii)=statv(ii).pass;
    end
    
    %All pass flags are '1'
    pass = sum(passv)>=length(passv);
    %and no tests died
    pass = pass && length(passv)==ebnodbs;
    passv;
    assert(pass)
endfunction

%Test with and without sample clock offset
function pass = test_timing_var(df,dA,M)
    pass = ebno_battery_test(1,0,df,dA,M)
    assert(pass)
    pass = pass && ebno_battery_test(0,0,df,dA,M)
    assert(pass)
endfunction

%Test with and without 1 Hz/S freq drift
function pass = test_drift_var(M)
    pass = test_timing_var(1,1,M)
    assert(pass)
    pass = pass && test_timing_var(0,1,M)
    assert(pass)
endfunction

function pass = test_fsk_battery()
    pass = test_mod_horuscfg_randbits;
    assert(pass)
    pass = pass && test_mod_horuscfgm4_randbits;
    assert(pass)
    pass = pass && test_drift_var(4);
    assert(pass)
    pass = pass && test_drift_var(2);
    assert(pass)
    if pass
        printf("***** All tests passed! *****\n");
    end
endfunction

function plot_fsk_bers(M=2)
    %Range of EbNodB over which to plot
    ebnodbrange = (3:13);
    
    berc = ones(1,length(ebnodbrange));
    bero = ones(1,length(ebnodbrange));
    berinc = ones(1,length(ebnodbrange));
    ebnodbs = length(ebnodbrange)
    mode = 2;
    %Replication of other parameters for parcellfun
    modev   = repmat(mode,1,ebnodbs);
    timingv = repmat(0,1,ebnodbs);
    fadingv = repmat(0,1,ebnodbs);
    dfv     = repmat(0,1,ebnodbs);
    dav     = repmat(1,1,ebnodbs);
    Mv     = repmat(M,1,ebnodbs);
    
    
    statv = pararrayfun(floor(1.25*nproc()),@tfsk_run_sim,modev,ebnodbrange,timingv,fadingv,dfv,dav,Mv);
    %statv = arrayfun(@tfsk_run_sim,modev,ebnodbrange,timingv,fadingv,dfv,dav,Mv);
    
    for ii = (1:length(statv))
        stat = statv(ii);
        berc(ii)=stat.berc;
        bero(ii)=stat.bero;
        berinc(ii)=stat.thrncoh;
    end
    clf;
    figure(M)
    
    semilogy(ebnodbrange, berinc,sprintf('r;%dFSK non-coherent theory;',M))
    hold on;
    semilogy(ebnodbrange, bero ,sprintf('g;Octave fsk horus %dFSK Demod;',M))
    semilogy(ebnodbrange, berc,sprintf('v;C fsk horus %dFSK Demod;',M))
    hold off;
    grid("minor");
    axis([min(ebnodbrange) max(ebnodbrange) 1E-5 1])
    legend("boxoff");
    xlabel("Eb/No (dB)");
    ylabel("Bit Error Rate (BER)")
 
endfunction


%test_fsk_battery
%plot_fsk_bers(2)
%plot_fsk_bers(4)
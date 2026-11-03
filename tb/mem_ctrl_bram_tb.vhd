-- mem_ctrl_bram_tb.vhd : VHDL-2008 self-checking testbench (xsim) for the BRAM
-- back-end, covering the RQ-106 "Back-End Checklist". A passive monitor models
-- the RAM from the bus and checks every response (data, order, exact latency).
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;
use std.env.all;
use work.mem_if_pkg.all;

entity mem_ctrl_bram_tb is
  generic (
    DEPTH_W : positive range 1 to MEM_DATA_W := 8;
    N_RAND  : natural := 3000
  );
end entity;

architecture sim of mem_ctrl_bram_tb is
  constant DEPTH   : natural := MEM_WORDS;       -- 76800
  constant LAST    : natural := DEPTH - 1;
  constant BRAM_LAT : natural := 1;              -- fixed per spec Latency table

  signal clk_i     : std_logic := '0';
  signal rst_n_i   : std_logic := '0';
  signal req       : mem_req_t := MEM_REQ_IDLE;
  signal req_ready : std_logic;
  signal rsp       : mem_rsp_t;
  signal mem_ready : std_logic;

  signal done      : boolean := false;
  signal errors    : natural := 0;
  signal n_reads   : natural := 0;
  signal n_checked : natural := 0;
  signal n_flushed : natural := 0;
  signal q_left    : natural := 0;
begin
  clk_i <= not clk_i after 5 ns when not done;

  dut : entity work.mem_ctrl_bram
    generic map (DEPTH_W => DEPTH_W)
    port map (clk_i => clk_i, rst_n_i => rst_n_i, req => req,
              req_ready => req_ready, rsp => rsp, mem_ready => mem_ready);

  ---------------------------------------------------------------------------
  -- monitor / scoreboard
  ---------------------------------------------------------------------------
  mon : process (clk_i)
    type model_t is array (0 to DEPTH - 1) of std_logic_vector(DEPTH_W - 1 downto 0);
    type flag_t  is array (0 to DEPTH - 1) of boolean;
    variable model   : model_t;
    variable written : flag_t := (others => false);  -- contents undefined until written
    type qd_t is array (0 to 15) of std_logic_vector(DEPTH_W - 1 downto 0);
    type qc_t is array (0 to 15) of natural;
    type qb_t is array (0 to 15) of boolean;
    variable qd : qd_t;
    variable qc : qc_t;
    variable qv : qb_t;                  -- compare data? (address was written)
    variable head, tail, cnt : natural := 0;
    variable cyc, err, nr, nc, nf, rst_cnt : natural := 0;
    variable a : natural;
  begin
    if rising_edge(clk_i) then
      cyc := cyc + 1;
      if rst_n_i = '0' then
        rst_cnt := rst_cnt + 1;
        if rst_cnt = 1 then               -- reset drops in-flight work
          nf := nf + cnt;
          cnt := 0; head := 0; tail := 0;
          written := (others => false);
        end if;
        if rsp.valid = '1' then
          report "rsp.valid during reset" severity error; err := err + 1;
        end if;
        if rst_cnt >= 2 and (mem_ready /= '0' or req_ready /= '0') then
          report "mem_ready/req_ready not low in reset" severity error; err := err + 1;
        end if;
      else
        rst_cnt := 0;
        -- response check
        if rsp.valid = '1' then
          if cnt = 0 then
            report "spurious rsp.valid at cycle " & integer'image(cyc) severity error;
            err := err + 1;
          else
            if qc(head) /= cyc then
              report "LATENCY: expected cycle " & integer'image(qc(head)) &
                     " got " & integer'image(cyc) severity error;
              err := err + 1;
            end if;
            if qv(head) and from_mem_data(rsp.rdata, DEPTH_W) /= qd(head) then
              report "DATA mismatch: got " & to_hstring(from_mem_data(rsp.rdata, DEPTH_W)) &
                     " exp " & to_hstring(qd(head)) severity error;
              err := err + 1;
            end if;
            head := (head + 1) mod 16; cnt := cnt - 1; nc := nc + 1;
          end if;
        elsif cnt > 0 and qc(head) = cyc then
          report "missing response at cycle " & integer'image(cyc) severity error;
          err := err + 1;
          head := (head + 1) mod 16; cnt := cnt - 1;
        end if;
        -- BRAM never stalls once mem_ready is high
        if mem_ready = '1' and req_ready /= '1' then
          report "req_ready low while mem_ready high" severity error; err := err + 1;
        end if;
        -- request accept
        if req.valid = '1' and req_ready = '1' then
          if mem_ready /= '1' then
            report "request accepted before mem_ready" severity error; err := err + 1;
          end if;
          a := to_integer(req.addr);
          if req.we = '1' then
            model(a) := from_mem_data(req.wdata, DEPTH_W); written(a) := true;
          else
            if written(a) then qd(tail) := model(a); end if;
            qv(tail) := written(a);
            qc(tail) := cyc + BRAM_LAT;
            tail := (tail + 1) mod 16; cnt := cnt + 1; nr := nr + 1;
          end if;
        end if;
      end if;
      errors <= err; n_reads <= nr; n_checked <= nc; n_flushed <= nf; q_left <= cnt;
    end if;
  end process;

  ---------------------------------------------------------------------------
  -- driver
  ---------------------------------------------------------------------------
  stim : process
    variable s1 : positive := 7;
    variable s2 : positive := 1234;
    variable r  : real;
    variable zero : std_logic_vector(DEPTH_W - 1 downto 0) := (others => '0');

    function pat(v : natural) return std_logic_vector is
    begin
      return std_logic_vector(resize(to_unsigned(v, 32), DEPTH_W));
    end function;

    -- one request; holds valid until the transfer edge; back-to-back capable
    procedure send(we : std_logic; addr : natural; data : std_logic_vector) is
    begin
      req.valid <= '1'; req.we <= we;
      req.addr  <= to_unsigned(addr, MEM_ADDR_W);
      req.wdata <= to_mem_data(data);
      loop
        wait until rising_edge(clk_i);
        exit when req_ready = '1';
      end loop;
      req.valid <= '0';
    end procedure;

    procedure idle(n : natural) is
    begin
      for i in 1 to n loop wait until rising_edge(clk_i); end loop;
    end procedure;

    impure function rnd_nat(maxv : natural) return natural is
    begin
      uniform(s1, s2, r);
      return natural(floor(r * real(maxv + 1))) mod (maxv + 1);
    end function;

    impure function rnd_slv return std_logic_vector is
      variable v : std_logic_vector(DEPTH_W - 1 downto 0);
    begin
      for i in v'range loop
        uniform(s1, s2, r);
        if r > 0.5 then v(i) := '1'; else v(i) := '0'; end if;
      end loop;
      return v;
    end function;

    variable a : natural;
  begin
    rst_n_i <= '0';
    idle(5);
    rst_n_i <= '1';
    -- first request goes out right at reset release: it must wait for mem_ready
    send('1', 0, pat(16#A5A5#));
    send('1', 1, pat(16#1234#));
    send('1', LAST - 1, pat(16#0F0F#));
    send('1', LAST, pat(16#5A5A#));
    idle(3);

    -- phase 1: first/last address and neighbours (aliasing), single reads
    send('0', 0, zero);       idle(3);
    send('0', LAST, zero);    idle(3);
    send('0', 1, zero);  send('0', LAST - 1, zero);
    idle(4);

    -- phase 2: back-to-back writes then reads
    for i in 0 to 15 loop send('1', 100 + i, pat(i * 7 + 1)); end loop;
    for i in 0 to 15 loop send('0', 100 + i, zero); end loop;
    idle(4);
    -- read on the cycle right after a write to the same address (rule 11)
    for i in 0 to 15 loop
      send('1', 500 + i, pat(i + 200));
      send('0', 500 + i, zero);
    end loop;
    idle(4);

    -- phase 3: random mixed traffic with idle gaps
    for i in 1 to N_RAND loop
      uniform(s1, s2, r);
      if r < 0.15 then
        idle(1);
      else
        if rnd_nat(9) < 3 then a := rnd_nat(31);
        elsif rnd_nat(19) = 0 then a := LAST - rnd_nat(3);
        else a := rnd_nat(LAST); end if;
        if rnd_nat(1) = 0 then send('1', a, rnd_slv);
        else send('0', a, zero); end if;
      end if;
    end loop;
    idle(BRAM_LAT + 4);

    -- phase 4: reset right after a read is accepted; no response may follow
    send('0', 40, zero);
    rst_n_i <= '0';
    idle(4);
    rst_n_i <= '1';
    send('1', 77, pat(16#5C#));
    send('0', 77, zero);
    idle(BRAM_LAT + 4);

    done <= true;
    wait;
  end process;

  final : process
  begin
    wait until done;
    wait for 1 ns;
    if errors = 0 and n_checked + n_flushed = n_reads and q_left = 0
       and n_flushed = 1 and n_checked > 100 then
      report "PASS: " & integer'image(n_checked) & " reads checked, DEPTH_W=" &
             integer'image(DEPTH_W);
    else
      report "FAIL: errors=" & integer'image(errors) & " checked=" &
             integer'image(n_checked) & " flushed=" & integer'image(n_flushed) &
             " reads=" & integer'image(n_reads) & " outstanding=" &
             integer'image(q_left) severity failure;
    end if;
    finish;
  end process;
end architecture;

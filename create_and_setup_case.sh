#!/bin/bash

# exit on error
set -e

# USER CONFIGURABLE OPTIONS
CASENAME=g.e22.TL319_t13.G1850ECOIAF_JRA_HR.test_16x16.002
CASEROOT_PARENT=/work2/08815/mlevy/frontera/codes/CESM/cesm2.2.0/cases

# RECOMMEND KEEPING THESE UNCHANGED
CESMROOT=/work2/08815/mlevy/frontera/codes/CESM/cesm2.2.0
COMPSET=G1850ECOIAF_JRA_HR
RES=TL319_t13
USER_STREAM_DIR=/work2/08815/mlevy/frontera/codes/frontera_highres_scripts/user_streams
SOURCEMOD_DIR=/work2/08815/mlevy/frontera/codes/frontera_highres_scripts/SourceMods
ref_dir=/work2/08815/mlevy/frontera/high_res_inputs/restarts
ref_case=g.e20.G.TL319_t13.control.001_contd
ref_date=0245-01-01
# 1958 - 1995 [245-282; 1-38]:
tavg_contents_override_file=/work2/08815/mlevy/frontera/high_res_inputs/tx0.1v3_tavg_contents_no5day
n_tavg_streams=3
# 1996 - 2018 [283-305; 39-61]:
# Alternate for Yassir: use 5day output for last 10 years => turn on 2009 (52)
# tavg_contents_override_file=/work2/08815/mlevy/frontera/high_res_inputs/tx0.1v3_tavg_contents
# n_tavg_streams=4
init_ecosys_init_file="/work2/08815/mlevy/frontera/high_res_inputs/ecosys_jan_IC_g.e22b05.G1850ECOIAF_JRA.TL319_g17.cocco.001_0123-01-01_POP_tx0.1v3_c200720.nc"


# 1. Create case
cd ${CESMROOT}/cime/scripts
./create_newcase --compset ${COMPSET} --res ${RES} --case ${CASEROOT_PARENT}/${CASENAME} --run-unsupported
cd ${CASEROOT_PARENT}/${CASENAME}


# 2. XML Changes:
#    * Smaller PE layout (less throughput, but less queue time
#    * Run for 3 months in 10 hour allocation
#    * Prognostic chlorophyll
#    * Run with coccolithophores
#    * Hybrid run from Alper's restarts
#    * Ecosys should be only passive tracer module (turn off ideal age)
#    * Also turn off age in the ice model
# NOTE: keep short-term archiving in default location
#       will need a separate script to generate time-series (where will time series go?)
echo "Making XML changes..."

#./xmlchange STOP_N=3,STOP_OPTION=nmonths,REST_N=1
#./xmlchange  --subgroup case.run JOB_WALLCLOCK_TIME=12:00:00
#./xmlchange PROJECT=CESM0010
./xmlchange OCN_CHL_TYPE=prognostic
./xmlchange OCN_BGC_CONFIG=latest+cocco
./xmlchange RUN_TYPE=hybrid,RUN_REFCASE=${ref_case},RUN_REFDATE=${ref_date}
./xmlchange OCN_TRACER_MODULES=ecosys
./xmlchange -a CICE_CONFIG_OPTS="-trage 0"

# 2.5 Additional XML Changes that Keith noticed:
#     * Change CPL_SEQ_OPTION
./xmlchange CPL_SEQ_OPTION=RASM_OPTION1

# 3. Run case-setup
echo "Running case.setup..."
./case.setup

# 4. Namelist changes
#    * Update tavg
#    * Will need to comment out init_ecosys variables after first run
#      (so continuation runs pull from restart file)
#    * CICE has a few changes from Alper's run as well
echo "Modifying user_nl files..."

cat >> user_nl_pop << EOF
! tavg namelist changes
ltavg_ignore_extra_streams = .true.
tavg_freq = 1 1 1 5
tavg_freq_opt = 'nmonth' 'nday' 'nyear' 'nday'
tavg_file_freq = 1 1 1 5
tavg_file_freq_opt = 'nmonth' 'nmonth' 'nyear' 'nday'
tavg_stream_filestrings = 'nmonth1' 'nday1' 'nyear1' 'nday5'

! Pick correct override file
! ----
tavg_contents_override_file = '${tavg_contents_override_file}'
n_tavg_streams = ${n_tavg_streams}

! 2x pulse in alternative atmospheric co2 concentration
! Enabled for years 0028 - 0032 [inclusive]
! atm_alt_co2_const = 568.634 ! originally 284.317

! Needed to get all MARBL diags defined correctly
lecosys_tavg_alt_co2 = .true.

! other changes from Alper (g.e20.G.TL319_t13.control.001_hfreq)
lcvmix = .false.
h_upper = 20.0
ltidal_mixing = .true.

! smaller timestep
dt_count = 816
time_mix_freq = 17

! First run needs initial conditions for ecosys
init_ecosys_option='ccsm_startup'
init_ecosys_init_file = '${init_ecosys_init_file}'
EOF

cat >> user_nl_cice << EOF
ndtd=2
r_snw=1.00
f_blkmask = .true.

histfreq = 'm','d','x','x','x'
histfreq_n = 1,1,0,0,0
f_hi = "mdxxx"
f_dvidtd = "mdxxx"
f_dvidtt = "mdxxx"
f_hs = "mdxxx"
f_apond_ai = "mxxxx"
f_aice = "mxxxx"
f_aicen = "mxxxx"
f_congel = "mxxxx"
f_daidtd = "mxxxx"
f_daidtt = "mxxxx"
f_frazil = "mxxxx"
f_fswabs = "mxxxx"
f_fswdn = "mxxxx"
f_fswthru = "mxxxx"
f_meltb = "mxxxx"
f_meltl = "mxxxx"
f_melts = "mxxxx"
f_meltt = "mxxxx"
f_vicen = "mxxxx"
f_vsnon = "mxxxx"
EOF


## Switch to JRA v1.5_noleap
cat >> user_nl_datm << EOF
  streams = "datm.streams.txt.CORE_IAF_JRA.GCGCS.PREC 245 1958 2021",
      "datm.streams.txt.CORE_IAF_JRA.GISS.LWDN 245 1958 2021",
      "datm.streams.txt.CORE_IAF_JRA.GISS.SWDN 245 1958 2021",
      "datm.streams.txt.CORE_IAF_JRA.NCEP.Q_10 245 1958 2021",
      "datm.streams.txt.CORE_IAF_JRA.NCEP.SLP_ 245 1958 2021",
      "datm.streams.txt.CORE_IAF_JRA.NCEP.T_10 245 1958 2021",
      "datm.streams.txt.CORE_IAF_JRA.NCEP.U_10 245 1958 2021",
      "datm.streams.txt.CORE_IAF_JRA.NCEP.V_10 245 1958 2021",
      "datm.streams.txt.CORE_IAF_JRA.CORE2.ArcFactor 245 1958 2021",
      "datm.streams.txt.presaero.clim_2000 1 1 1"
EOF

cat >> user_nl_drof << EOF
  streams = "drof.streams.txt.rof.iaf_jra 1 1958 2021"
EOF

# Copy user_*.streams.txt.* to case directory
cp ${USER_STREAM_DIR}/user_* .

# 5. SourceMods
#    * Modify dz*DOP_loss_P_bal threshold to reduce warnings in cesm.log
echo "copying file(s) to SourceMods..."

cp ${SOURCEMOD_DIR}/marbl_interior_tendency_mod.F90 SourceMods/src.pop/

# 6. Set up rpointers
run_dir=`./xmlquery RUNDIR --value`
echo "copying restart files and rpointer files to ${run_dir}..."

cp -v ${ref_dir}/${ref_date}-00000/* ${run_dir}
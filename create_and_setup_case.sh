#!/bin/bash

# NOTE: To get email notifications from run, set up ~/.cime/config
# exit on error
set -e

# USER CONFIGURABLE OPTIONS
CASENAME=g.e22.TL319_t13.G1850ECOIAF_JRA_HR.test_15x15.4p2z.ndep_shr_stream.003
CASEROOT_PARENT=/work2/08815/mlevy/frontera/codes/CESM/cesm2.2.0/cases

# RECOMMEND KEEPING THESE UNCHANGED
SCRIPT_DIR=`cd -P $(dirname $0) ; echo $PWD`
CESMROOT=/work2/08815/mlevy/frontera/codes/CESM/cesm2.2.0
COMPSET=G1850ECOIAF_JRA_HR
#COMPSET="2000_DATM%JRA_SLND_CICE_POP2_DROF%JRA_SGLC_SWAV"
RES=TL319_t13
USER_STREAM_DIR=${SCRIPT_DIR}/user_streams
SOURCEMOD_DIR=${SCRIPT_DIR}/SourceMods
ref_dir=/work2/08815/mlevy/frontera/high_res_inputs/restarts
ref_case=g.e20.G.TL319_t13.control.001_contd
ref_date=0245-01-01
# 1958 - 1995 [245-282; 1-38]:
tavg_contents_override_file=${SCRIPT_DIR}/tavg_contents/tx0.1v3_tavg_contents_no5day_4p2z
n_tavg_streams=3
# 1996 - 2018 [283-305; 39-61]:
# Alternate for Yassir: use 5day output for last 10 years => turn on 2009 (52)
# tavg_contents_override_file=/work2/08815/mlevy/frontera/high_res_inputs/tx0.1v3_tavg_contents
# n_tavg_streams=4
init_ecosys_init_file="/work2/08815/mlevy/frontera/high_res_inputs/ecosys_jan_IC_g.e22.GOMIPECOIAF_JRA-1p4-2018.TL319_g17.4p2z.001_0306-01-01_POP_tx0.1v3_c220701.nc"


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

./xmlchange OCN_CHL_TYPE=prognostic
./xmlchange OCN_CO2_TYPE=diagnostic
./xmlchange CCSM_BGC=CO2A
./xmlchange RUN_TYPE=hybrid,RUN_REFCASE=${ref_case},RUN_REFDATE=${ref_date}
./xmlchange RUN_STARTDATE=1958-01-01
./xmlchange OCN_TRACER_MODULES=ecosys
./xmlchange -a CICE_CONFIG_OPTS="-trage 0"
./xmlchange DATM_MODE=CORE_IAF_JRA,DROF_MODE=IAF_JRA
./xmlchange DATM_CO2_TSERIES=omip
./xmlchange REST_N=1,REST_OPTION=nmonths
./xmlchange DOUT_S_SAVE_INTERIM_RESTART_FILES=TRUE
###
# 16 x 16 blocks (1.1 SYPD, 510k cpu-hours / year)
###
#./xmlchange NTASKS_OCN=22626
#./xmlchange STOP_N=2,STOP_OPTION=nyears
#./xmlchange --subgroup case.run JOB_WALLCLOCK_TIME=48:00:00
###
# 15 x 15 blocks (1.4 SYPD, 460k cpu-hours / year)
###
./xmlchange NTASKS_OCN=25654
./xmlchange STOP_N=2,STOP_OPTION=nyears
./xmlchange --subgroup case.run JOB_WALLCLOCK_TIME=40:00:00
###
# 12 x 12 blocks (1.7 SYPD, 570k cpu-hours / year)
###
#./xmlchange NTASKS_OCN=39661
#./xmlchange STOP_N=3,STOP_OPTION=nyears
#./xmlchange --subgroup case.run JOB_WALLCLOCK_TIME=48:00:00

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

! Needed to get all MARBL diags defined correctly
lecosys_tavg_alt_co2 = .true.

! other changes from Alper (g.e20.G.TL319_t13.control.001_hfreq)
lcvmix = .false.
h_upper = 20.0
ltidal_mixing = .true.

! other changes from Fred (g.e21.GIAF.TL319_t13.5thCyc.ice.001)
shf_strong_restore = 79.1
shf_strong_restore_ms = 79.1
sfwf_strong_restore = 0.56
sfwf_strong_restore_ms = 0.56

! smaller timestep
dt_count = 816
time_mix_freq = 17

! ndep from shr_stream
ndep_data_type = 'shr_stream'
ndep_shr_stream_file = '/scratch1/08815/mlevy/tmp_inputdata/ocn_Ndep_transient_forcing_x0.1_220709.nc'
ndep_shr_stream_scale_factor = 7.1429e+06
ndep_shr_stream_year_align = 1958
ndep_shr_stream_year_first = 1958
ndep_shr_stream_year_last = 2021

! First run needs initial conditions for ecosys
init_ecosys_option='ccsm_startup'
init_ecosys_init_file = '${init_ecosys_init_file}'
EOF

cat >> user_nl_cice << EOF
ndtd=2
dt_mlt=0.5
r_snw=1.60
rsnw_mlt = 1000.
f_blkmask = .true.

histfreq = 'm','d','x','x','x'
histfreq_n = 1,1,0,0,0
f_aice = "mdxxx"
f_congel = "mdxxx"
f_daidtd = "mdxxx"
f_daidtt = "mdxxx"
f_dvidtd = "mdxxx"
f_dvidtt = "mdxxx"
f_fcondtop_ai = "mdxxx"
f_flat = "mdxxx"
f_flwdn = "mdxxx"
f_frazil = "mdxxx"
f_fsens = "mdxxx"
f_fswabs = "mdxxx"
f_fswdn = "mdxxx"
f_fswthru = "mdxxx"
f_hi = "mdxxx"
f_hs = "mdxxx"
f_meltb = "mdxxx"
f_meltl = "mdxxx"
f_melts = "mdxxx"
f_meltt = "mdxxx"
f_snoice = "mdxxx"
f_uvel = "mdxxx"
f_vvel = "mdxxx"

f_aicen = "mxxxx"
f_apond_ai = "mxxxx"
f_vicen = "mxxxx"
f_vsnon = "mxxxx"
EOF

## Switch to JRA v1.5_noleap
cat >> user_nl_datm << EOF
  streams = "datm.streams.txt.CORE_IAF_JRA.GCGCS.PREC 1958 1958 2021",
      "datm.streams.txt.CORE_IAF_JRA.GISS.LWDN 1958 1958 2021",
      "datm.streams.txt.CORE_IAF_JRA.GISS.SWDN 1958 1958 2021",
      "datm.streams.txt.CORE_IAF_JRA.NCEP.Q_10 1958 1958 2021",
      "datm.streams.txt.CORE_IAF_JRA.NCEP.SLP_ 1958 1958 2021",
      "datm.streams.txt.CORE_IAF_JRA.NCEP.T_10 1958 1958 2021",
      "datm.streams.txt.CORE_IAF_JRA.NCEP.U_10 1958 1958 2021",
      "datm.streams.txt.CORE_IAF_JRA.NCEP.V_10 1958 1958 2021",
      "datm.streams.txt.presaero.clim_1850 1958 1958 2021",
      "datm.streams.txt.co2tseries.omip 1958 1958 2021"
EOF

cat >> user_nl_drof << EOF
  streams = "drof.streams.txt.rof.iaf_jra 1958 1958 2021"
EOF

# user_nl_marbl is a big file, don't want to include it all in this script
cp ${USER_STREAM_DIR}/../user_nl/user_nl_marbl .

# Copy user_*.streams.txt.* to case directory
cp ${USER_STREAM_DIR}/user_* .

# 5. SourceMods
#    * Modify dz*DOP_loss_P_bal threshold to reduce warnings in cesm.log
echo "copying file(s) to SourceMods..."

for file in marbl_interior_tendency_mod.F90 \
            marbl_diagnostics_mod.F90 \
            marbl_interface_private_types.F90 \
            baroclinic.F90 \
            forcing.F90 \
            forcing_shf.F90 \
            passive_tracers.F90 \
            tavg.F90
do
  cp ${SOURCEMOD_DIR}/${file} SourceMods/src.pop/
done

# 6. Set up rpointers
run_dir=`./xmlquery RUNDIR --value`
echo "copying restart files and rpointer files to ${run_dir}..."

cp -v ${ref_dir}/${ref_date}-00000/* ${run_dir}

echo ""
echo "SUCCESS! Created ${CASEROOT_PARENT}/${CASENAME}"
echo "cd to that directory and run 'idev' to get a compute node, then run ./case.build"

# Next run "idev" to get interactive node, and then run ./case.build
# (from what I can tell, srun will launch 56 concurrent instances of case.build)

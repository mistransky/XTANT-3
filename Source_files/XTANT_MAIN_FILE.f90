!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
! XTANT-3: X-ray-induced Thermal And Nonthermal Transitions
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
! This file is part of XTANT
!
! Copyright (C) 2012-2023 Nikita Medvedev
!
! XTANT is free software: you can redistribute it and/or modify it under
! the terms of the GNU Lesser General Public License as published by
! the Free Software Foundation, either version 3 of the License, or
! (at your option) any later version.
!
! Although we endeavour to ensure that the code XTANT and results delivered are correct,
! no warranty is given as to its accuracy. We assume no responsibility for possible errors or omissions.
! We shall not be liable for any damage arising from the use of this code or its parts
! or any results produced with it, or from any action or decision taken
! as a result of using this code or any related material.
!
! This code is distributed as is for non-commercial peaceful purposes only,
! such as research and education. It is explicitly prohibited to use the code,
! its parts, its results or any related material for military-related and other than peaceful purposes.
!
! By using this code or its materials, you agree with these terms and conditions.
! 000000000000000000000000000000000000000000000000000000000000
! The hybrid code is written by
!
! Dr. Nikita Medvedev
!
! as a part of research at
! CFEL at DESY, Hamburg, Germany 2011-2016,
! and in the Institute of Physics of CAS, Prague, Czechia 2016-2022
!
! The model is described in: 
! https://arxiv.org/abs/1805.07524
!
! Should you have any questions, contact the author: nikita.medvedev@fzu.cz
! Or by private email: n.a.medvedev@gmail.com
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
! CONVENTIONS OF PROGRAMMING:
! 1) All global variables start with "g_", e.g. g_numpar, and all defined in the module "Variables"
! 2) All modular variable names are defined starting as "m_", e.g. "m_number"
! 3) All local variables used within subrounies should NOT start with "g_" or "m_"
! 4) Add a comment after each subroutine and function specifying in which module it can be found
! 5) Leave comments describing what EACH LINE of the code is doing
! 6) Each end(smth) statement should be commented to which block it belongs, e.g.: if (i<k) then ... endif ! (i<k)
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!


PROGRAM XTANT
!MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM
! Initiate modules with all the 'use' statements collected in a separate file:
include 'Use_statements.f90'   	! include part of the code from an external file

implicit none


!MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM
! Print XTANT label on the screen
#ifdef OMP_inside
   call XTANT_label(6, 1)   ! module "Dealing_with_output_files"
#else ! if you set to use OpenMP in compiling: 'make OMP=no'
   call XTANT_label(6, 4)   ! module "Dealing_with_output_files"
#endif

!MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM
g_numpar%which_input = 0 ! starting with the default input files
g_numpar%allow_rotate = .false. ! do not allow rotation of the target, remove angular momentum from initial conditions
1984 g_Err%Err = .false.
g_Err%Err_descript = ''	! start with an empty string
g_Err%File_Num = 99
open(UNIT = g_Err%File_Num, FILE = 'OUTPUT_Error_log.dat')

! Check if the user needs any additional info (by setting the flags):
call get_add_data(g_numpar%path_sep, change_size=g_numpar%change_size, contin=g_Err%Err, &
                  allow_rotate=g_numpar%allow_rotate, verbose=g_numpar%verbose) ! module "Read_input_data"
if (g_numpar%verbose) call print_time_step('Verbose option is on, XTANT is going to be a chatterbox', msec=.true.)

if (g_Err%Err) goto 2016     ! if the USER does not want to run the calculations
! Otherwise, run the calculations:
call random_seed() ! standard FORTRAN seeding of random numbers
call date_and_time(values=g_c1) ! standard FORTRAN time and date
g_ctim=g_c1	! save the timestamp
!IIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIII

call print_time('Attempting to start XTANT at', ind=0) ! prints out the current time, module "Little_subroutines"

! Set all the initial data, read and create files:
! Read input files:
if (g_numpar%which_input > 0) then ! it's not the first run
   print*, '# It is run for input files number:', g_numpar%which_input
   call Read_Input_Files(g_matter, g_numpar, g_laser, g_Scell, g_Err, g_numpar%which_input) ! module "Read_input_data"
else ! it is the first run:
   print*, '# It is the first run'
   call Read_Input_Files(g_matter, g_numpar, g_laser, g_Scell, g_Err) ! module "Read_input_data"
endif
if (g_Err%Err) goto 2012	! if there was an error in the input files, cannot continue, go to the end...
! Printout additional info, if requested:
if (g_numpar%verbose) call print_time_step('Input files read succesfully:', msec=.true.)

! if you set to use OpenMP in compiling: "make"
#ifdef OMP_inside
   call OMP_SET_DYNAMIC(0) ! standard openmp subroutine
   call OMP_SET_NUM_THREADS(g_numpar%NOMP) ! number of threads for openmp defined in INPUT_PARAMETERS.txt
#else ! if you set to use OpenMP in compiling: 'make OMP=no'
!   print*, 'No openmp to deal with...'
!   pause 'NO OPENMP'
#endif

! Starting time, to give enough time for system to thermalize before the pulse:
call set_starting_time(g_laser, g_time, g_numpar%t_start, g_numpar%t_NA, g_numpar%t_Te_Ee) ! module "Little_subroutines"
! And check if user wants to reset it:
call reset_dt(g_numpar, g_matter, g_time)   ! module "Dealing_with_output_files"

! Print the title of the program and used parameters on the screen:
!call Print_title(6,g_Scell,g_matter,g_laser,g_numpar) ! module "Dealing_with_output_files"
! call print_time('Attempting to start at', ind=0) ! prints out the current time, module "Little_subroutines"

! Prepare initial conditions (read supercell and atomic positions from the files):
call set_initial_configuration(g_Scell, g_matter, g_numpar, g_laser, g_MC, g_Err) ! module "Initial_configuration"
if (g_Err%Err) goto 2012	! if there was an error in preparing the initial configuration, cannot continue, go to the end...
if (g_numpar%verbose) call print_time_step('Initial configuration set succesfully:', msec=.true.)


! Print the title of the program and used parameters on the screen:
call Print_title(6, g_Scell, g_matter, g_laser, g_numpar, -1) ! module "Dealing_with_output_files"
call print_time('Start at', ind=0) ! prints out the current time, module "Little_subroutines"


! Read (or create) electronic mean free paths (both, inelastic and elastic):
call get_MFPs(g_Scell, 1, g_matter, g_laser, g_numpar, g_Scell(1)%TeeV, g_Err) ! module "MC_cross_sections"
if (g_Err%Err) goto 2012	! if there was an error in the input files, cannot continue, go to the end...
if (g_numpar%verbose) call print_time_step('Electron mean free paths set succesfully:', msec=.true.)

! Read (or create) photonic mean free paths:
call get_photon_attenuation(g_matter, g_laser, g_numpar, g_Err) ! module "MC_cross_sections"
if (g_Err%Err) goto 2012	! if there was an error in the input files, cannot continue, go to the end...
if (g_numpar%verbose) call print_time_step('Photon attenuation lengths set succesfully:', msec=.true.)

if (.not.g_numpar%do_path_coordinate) then  ! only for real calculations, not for coordinate path
   call save_last_timestep(g_Scell) ! save atomic before making next time-step, module "Atomic_tools"
endif

! Create the folder where output files will be storred, and prepare the files:
call prepare_output_files(g_Scell,g_matter, g_laser, g_numpar, g_Scell(1)%TB_Hamil(1,1), g_Scell(1)%TB_Repuls(1,1), g_Err) ! module "Dealing_with_output_files"
if (g_Err%Err) goto 2012 	! if there was an error in preparing the output files, cannot continue, go to the end...
if (g_numpar%verbose) call print_time_step('Output directory prepared succesfully:', msec=.true.)

!IIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIII
! Project-specific analysis of C60:
! call C60_vdW_vs_Coulomb(g_Scell, g_numpar, g_matter, layers=2) ! Module "TB"
! call C60_crystal_construction(g_Scell, g_matter) ! module "Atomic_tools"
! call Coulomb_beats_vdW(g_Scell, g_numpar) ! see below

!IIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIII
! If user set '-size' option to vary the super-cell size:
if (g_numpar%change_size) then
   call vary_size(Err=g_Err%Err) ! see below, used for testing
   if (g_Err%Err) goto 2012      ! if the USER does not want to run the calculations
endif
!IIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIII
! If user set to calculate the coordinate path between two phases of material:

if (g_numpar%do_path_coordinate) then
   call coordinate_path( )  ! below
   if (g_Err%Err) goto 2012      ! if the USER does not want to run the calculations
endif
!IIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIII

! After the initial data are read, and necessay files created,
! now we can proceed with the real calculations

! Contruct TB Hamiltonian, diagonalize to get energy levels, get forces for atoms and supercell:
call get_Hamilonian_and_E(g_Scell, g_numpar, g_matter, 1, g_Err, g_time) ! module "TB"
if (g_numpar%verbose) call print_time_step('Initial Hamiltonian prepared succesfully:', msec=.true.)

! Thermalization step for low-energy electrons (used only in relaxation-time approximation):
call Electron_thermalization(g_Scell, g_numpar, skip_thermalization=.true.) ! module "Electron_tools"

! Get global energy of the system at the beginning:
call get_glob_energy(g_Scell, g_matter) ! module "Electron_tools"
if (g_numpar%verbose) call print_time_step('Initial energy prepared succesfully:', msec=.true.)

! Get initial optical coefficients:
call get_optical_parameters(g_numpar, g_matter, g_Scell, g_Err) ! module "Optical_parameters"
if (g_numpar%verbose) call print_time_step('Optical parameters prepared succesfully:', msec=.true.)

! Get initial DOS:
call get_DOS(g_numpar, g_matter, g_Scell, g_Err)	! module "TB"
if (g_numpar%verbose) call print_time_step('DOS calculated succesfully:', msec=.true.)

! Get current Mulliken charges, if required:
call get_Mulliken(g_numpar%Mulliken_model, g_numpar%mask_DOS, g_numpar%DOS_weights, g_Scell(1)%Ha, &
                  g_Scell(1)%fe, g_matter, g_Scell(1)%MDAtoms, g_matter%Atoms(:)%mulliken_Ne) ! module "TB"
if (g_numpar%verbose) call print_time_step('Mulliken charges calculated succesfully:', msec=.true.)

! Get the pressure in the atomic system:
call Get_pressure(g_Scell, g_numpar, g_matter, g_Scell(1)%Pressure,  g_Scell(1)%Stress)	! module "TB"
if (g_numpar%verbose) call print_time_step('Pressure calculated succesfully:', msec=.true.)

! Calculate the mean square displacement of all atoms:
call get_mean_square_displacement(g_Scell, g_matter, g_Scell(1)%MSD,  g_Scell(1)%MSDP, g_numpar%MSD_power)	! module "Atomic_tools"
if (g_numpar%verbose) call print_time_step('Mean displacement calculated succesfully:', msec=.true.)

! Calculate electron heat capacity, entropy:
call get_electronic_thermal_parameters(g_numpar, g_Scell, 1, g_matter, g_Err) ! module "TB"

! And save the (low-energy part of the) distribution on the grid, if required
! (its high-energy part is inside of MC_Propagate subroutine):
call get_low_energy_distribution(g_Scell(1), g_numpar) ! module "Electron_tools"


! Calculate configurational temperature:
! call Get_configurational_temperature(g_Scell, g_numpar, g_Scell(1)%Tconf)	! module "TB"

! Save initial step in output:
call write_output_files(g_numpar, g_time, g_matter, g_Scell) ! module "Dealing_with_output_files"
if (g_numpar%verbose) call print_time_step('Initial output files set succesfully:', msec=.true.)

!DDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD
! Now we can proceed with time:
! Print out the starting time:
call print_time_step('Simulation time:', g_time, msec=.true.)   ! module "Little_subroutines"

i_test = 0 !  count number of timesteps
g_dt_save = 0.0d0
do while (g_time .LT. g_numpar%t_total)
   i_test = i_test + 1
   ! If there is a grid for changing time-step, change it:
   call reset_dt(g_numpar, g_matter, g_time)  ! module "Dealing_with_output_files"

   AT_MOVE_1:if (g_numpar%do_atoms) then ! atoms are allowed to be moving:
      !1111111111111111111111111111111111111111111111111111111111
      ! Update atomic data on previous timestep and move further:
      call save_last_timestep(g_Scell) ! module "Atomic_tools"
      ! Make the MD timestep (first part, in the case of Verlet):
      call MD_step(g_Scell, g_matter, g_numpar, g_time, g_Err)  ! module "TB"
      if (g_numpar%verbose) call print_time_step('First step of MD step succesful:', g_time, msec=.true.)
      
      !2222222222222222222222222222222222222222222222222222222
      ! Nonadiabatic electron-ion coupling:
      call Electron_ion_coupling(g_time, g_matter, g_numpar, g_Scell, g_Err) !  module "TB"
      if (g_numpar%verbose) call print_time_step('Electron_ion_coupling succesful:', g_time, msec=.true.)

      ! Quenching of atoms (zero-temperature MD):
      call Cooling_atoms(g_numpar, g_matter, g_Scell, g_time, g_numpar%at_cool_dt, g_numpar%at_cool_start, g_numpar%do_cool) ! module "Atomic_tools"

      ! Berendsen thermostat (mimicing energy transport; only if included):
      if (g_numpar%Transport_e) then ! for electrons
         ! Include Berendsen thermostat in the electronic system:
         call Electron_transport(1, g_time, g_Scell, g_numpar, g_matter, g_numpar%dt, g_matter%tau_bath_e, g_Err) ! module "Transport"
         if (g_numpar%verbose) call print_time_step('Electron Berendsen thermostat succesful:', g_time, msec=.true.)
      endif
      if (g_numpar%Transport) then ! for atoms
         ! Include Berendsen thermostat in the atomic system:
         call Atomic_heat_transport(1, g_Scell, g_matter, g_numpar%dt, g_matter%tau_bath) ! module "Transport"
         ! Include change of the affected layer for calculation of optical constants:
         call Change_affected_layer(1, g_Scell(1)%eps%dd, g_Scell, g_numpar%dt, g_matter%tau_bath)  ! module "Transport"
         if (g_numpar%verbose) call print_time_step('Atomic Berendsen thermostat succesful:', g_time, msec=.true.)

      endif
   endif AT_MOVE_1

   ! Monte-Carlo for photons, high-energy electrons, and core holes:
   call MC_Propagate(g_MC, g_numpar, g_matter, g_Scell, g_laser, g_time, g_Err) ! module "Monte_Carlo"
   if (g_numpar%verbose) call print_time_step('Monte Carlo model executed succesfully:', g_time, msec=.true.) ! module "Little_subroutines"

   ! Thermalization step for low-energy electrons (used only in relaxation-time approximation):
   call Electron_thermalization(g_Scell, g_numpar) ! module "Electron_tools"

   ! And save the (low-energy part of the) distribution on the grid, if required
   ! (its high-energy part is inside of MC_Propagate subroutine):
   call get_low_energy_distribution(g_Scell(1), g_numpar) ! module "Electron_tools"

   ! Update corresponding energies of the system:
   call update_nrg_after_change(g_Scell, g_matter, g_numpar, g_time, g_Err) ! module "TB"

   !3333333333333333333333333333333333333333333333333333333333
   AT_MOVE_2:if (g_numpar%do_atoms) then ! atoms are allowed to be moving:
      ! Choose which MD propagator to use:
      select case(g_numpar%MD_algo)
      case default  ! velocity Verlet (2d order):
         !velocities update in the Verlet algorithm:
         call save_last_timestep(g_Scell) ! module "Atomic_tools"
         ! Atomic Verlet step:
         call make_time_step_atoms(g_Scell, g_matter, g_numpar, 1)     ! module "Atomic_tools"
         ! Supercell Verlet step:
         call make_time_step_supercell(g_Scell, g_matter, g_numpar, 1) ! supercell Verlet step, module "Atomic_tools"
         ! Update corresponding energies of the system:
         call get_new_energies(g_Scell, g_matter, g_numpar, g_time, g_Err) ! module "TB"
      case (1)  ! Youshida (4th order)
         ! No divided steps, all of them are performed above
      case (2)  ! Martyna (4th order)
         ! No divided steps for atoms, but use Verlet for supercell:
         !velocities update in the Verlet algorithm:
         call save_last_timestep(g_Scell) ! module "Atomic_tools"
         ! Supercell Verlet step:
         call make_time_step_supercell(g_Scell, g_matter, g_numpar, 1) ! supercell Verlet step, module "Atomic_tools"
         ! Update corresponding energies of the system:
         call get_new_energies(g_Scell, g_matter, g_numpar, g_time, g_Err) ! module "TB"
      endselect
   endif AT_MOVE_2
   if (g_numpar%verbose) call print_time_step('Second step of MD step succesful:', g_time, msec=.true.) ! module "Little_subroutines"

   !oooooooooooooooooooooooooooooooooooooooooooooooooooooooooo
   g_time = g_time + g_numpar%dt        ! [fs] next time-step
   g_dt_save = g_dt_save + g_numpar%dt  ! [fs] for tracing when to save the output data
   ! Write current data into output files:
   if (g_dt_save .GE. g_numpar%dt_save - 1d-6) then
      ! Print out the curent time-step
      call print_time_step('Simulation time:', g_time, msec=.true.)   ! module "Little_subroutines"
      ! Get current optical coefficients:
      call get_optical_parameters(g_numpar, g_matter, g_Scell, g_Err) ! module "Optical_parameters"
      ! Get current DOS:
      call get_DOS(g_numpar, g_matter, g_Scell, g_Err)	! module "TB"
      
      ! Get current Mulliken charges, if required:
      call get_Mulliken(g_numpar%Mulliken_model, g_numpar%mask_DOS, g_numpar%DOS_weights, g_Scell(1)%Ha, &
                            g_Scell(1)%fe, g_matter, g_Scell(1)%MDAtoms, g_matter%Atoms(:)%mulliken_Ne) ! module "TB"
      
      ! Get current pressure in the system:
      call Get_pressure(g_Scell, g_numpar, g_matter, g_Scell(1)%Pressure, g_Scell(1)%Stress)	! module "TB"
      ! Calculate the mean square displacement of all atoms:
      call get_mean_square_displacement(g_Scell, g_matter, g_Scell(1)%MSD, g_Scell(1)%MSDP, g_numpar%MSD_power)	! module "Atomic_tools"
      ! Calculate electron heat capacity, entropy:
      call get_electronic_thermal_parameters(g_numpar, g_Scell, 1, g_matter, g_Err) ! module "TB"

      ! Calculate configurational temperature:
!       call Get_configurational_temperature(g_Scell, g_numpar, g_Scell(1)%Tconf)	! module "TB"
      ! Save current output data:
      call write_output_files(g_numpar, g_time, g_matter, g_Scell)    ! module "Dealing_with_output_files"
      ! Communicate with the program (program reads your commands from the communication-file):
      call communicate(g_numpar%FN_communication, g_time, g_numpar, g_matter) ! module "Dealing_with_output_files"
      g_dt_save = 0.0d0

      if (g_numpar%verbose) call print_time_step('Output files written succesfully:', g_time, msec=.true.)   ! module "Little_subroutines"
   endif
   !oooooooooooooooooooooooooooooooooooooooooooooooooooooooooo
enddo

!FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF
! Finish execution of the program:
call close_file('delete', FN=g_numpar%FN_communication) ! module "Dealing_with_files"
2012 continue

INQUIRE(UNIT = g_Err%File_Num, opened=file_opened, name=chtest)
if (file_opened) then
   flush(g_Err%File_Num)
endif
! Closing the opened files:
if (g_Err%Err) then
   call close_file('close', FN=g_Err%File_Num) ! module "Dealing_with_files"
else ! if there was no error, no need to keep the file, delete it
   call close_file('delete', FN=g_Err%File_Num) ! module "Dealing_with_files"
endif
call close_save_files()           ! module "Dealing_with_files"
call close_output_files(g_Scell, g_numpar) ! module "Dealing_with_files"

if (g_numpar%verbose) call print_time_step('Opened files closed succesfully', msec=.true.)

!CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC
! Convolve output files with finite duration of the probe pulse:
!if (g_numpar%do_drude) then
if (g_Scell(1)%eps%tau > 0.0d0) then
   call convolve_output(g_Scell, g_numpar)  ! module "Dealing_with_output_files"
   print*, 'Convolution with the probe pulse is performed'
else
   print*, 'No convolution with the probe pulse was required'
endif

!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
! Printing out the duration of the program, starting and ending time and date:
call parse_time(chtest, c0_in=g_ctim) ! module "Little_subroutines"
write(*,'(a,a)') 'Duration of execution of program: ', trim(adjustl(chtest))

call save_duration(g_matter, g_numpar, trim(adjustl(chtest))) ! module "Dealing_with_output_files"

call print_time('Started  at', ctim=g_ctim) ! module "Little_subroutines"
call print_time('Finished at') ! module "Little_subroutines"
write(*,'(a)') trim(adjustl(m_starline))

!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
write(*,'(a)')  'Executing gnuplot scripts to create plots...'
call execute_all_gnuplots(trim(adjustl(g_numpar%output_path))//trim(adjustl(g_numpar%path_sep)))       ! module "Write_output"
if (g_numpar%verbose) call print_time_step('Gnuplot calles executed succesfully', msec=.true.)

!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!Check if there is another set of input files to run next simulation:
 g_numpar%which_input = g_numpar%which_input + 1
 chtest = 'INPUT_DATA'//g_numpar%path_sep//'INPUT_MATERIAL'
 write(chtest2,'(i3)') g_numpar%which_input
 write(chtest,'(a,a,a,a)') trim(adjustl(chtest)), '_', trim(adjustl(chtest2)), '.txt'
 inquire(file=trim(adjustl(chtest)),exist=file_exists)    ! check if input file excists
 if (file_exists) then ! one file exists
    chtest = 'INPUT_DATA'//g_numpar%path_sep//'NUMERICAL_PARAMETERS'
    write(chtest,'(a,a,a,a)') trim(adjustl(chtest)), '_', trim(adjustl(chtest2)), '.txt'
    inquire(file=trim(adjustl(chtest)),exist=file_exists)    ! check if input file excists
    if (file_exists) then ! second input file exists
       write(*,'(a)') trim(adjustl(m_starline))
       write(*,'(a,a)')  'Another set of input parameter files exists: ', trim(adjustl(chtest))
       write(*,'(a)')    'Running XTANT again for these new parameters...'
       call deallocate_all() ! module "Variables"
       goto 1984 ! go to the beginning and run the program again for the new input files
    else
       write(*,'(a,a,a)')  'File ', trim(adjustl(chtest)), ' could not be found.'
       write(*,'(a)')  'XTANT has done its duty, XTANT can go...'
    endif
 else
    write(*,'(a)')  'XTANT has done its duty, XTANT can go...'
 endif
 write(*,'(a)') trim(adjustl(m_starline))

2016 continue



 contains


!TTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTT
! Use this for obtaining coordinate path between two phases:
subroutine coordinate_path( )
!    integer, intent(in) :: ind ! 0=NVE, 1=NPH
   integer :: i, i_step, i_at, Nat, N_steps, SCN
   type(Atom), dimension(:), allocatable :: MDAtoms ! if more then one supercell
   type(Atom), dimension(:), allocatable :: MDAtoms0 ! if more then one supercell
   real(8), dimension(3,3) :: supce, supce0 	! [A] length of super-cell
   real(8), dimension(3,3) :: Vsupce, Vsupce0    ! Derivatives of Super-cell vectors (velosities)
   real(8) :: sc_fact
   
   write(6, '(a)') 'Starting subroutine coordinate_path ...'
   
   open(UNIT = 100, FILE = 'OUTPUT_coordinate_path.dat') !<-
   
   Nat = size(g_Scell(1)%MDatoms)   ! number of atoms in the supercell
   allocate(MDAtoms(Nat))
   allocate(MDAtoms0(Nat))
   SCN = 1
   do i = 1, Nat ! to use below
      MDAtoms(i)%S0(:) = g_Scell(SCN)%MDAtoms(i)%S0(:)
      MDAtoms(i)%SV0(:) = g_Scell(SCN)%MDAtoms(i)%SV0(:)
      MDAtoms(i)%S(:) = g_Scell(SCN)%MDAtoms(i)%S(:)
      MDAtoms(i)%SV(:) = g_Scell(SCN)%MDAtoms(i)%SV(:)
      ! Take care of boundary crossing:
      if ( abs(MDAtoms(i)%S(1) - MDAtoms(i)%S0(1)) > 0.5 ) then
         if (MDAtoms(i)%S(1) > MDAtoms(i)%S0(1)) then
            MDAtoms(i)%S0(1) = MDAtoms(i)%S0(1) + 1.0d0
         else
            MDAtoms(i)%S(1) = MDAtoms(i)%S(1) + 1.0d0
         endif
      endif
      
      if ( abs(MDAtoms(i)%S(2) - MDAtoms(i)%S0(2)) > 0.5 ) then
         if (MDAtoms(i)%S(2) > MDAtoms(i)%S0(2)) then
            MDAtoms(i)%S0(2) = MDAtoms(i)%S0(2) + 1.0d0
         else
            MDAtoms(i)%S(2) = MDAtoms(i)%S(2) + 1.0d0
         endif
      endif
      
      if ( abs(MDAtoms(i)%S(3) - MDAtoms(i)%S0(3)) > 0.5 ) then
         if (MDAtoms(i)%S(3) > MDAtoms(i)%S0(3)) then
            MDAtoms(i)%S0(3) = MDAtoms(i)%S0(3) + 1.0d0
         else
            MDAtoms(i)%S(3) = MDAtoms(i)%S(3) + 1.0d0
         endif
      endif
      
!       write(6,'(i3,f,f,f,f,f,f)') i, g_Scell(SCN)%MDAtoms(i)%S0(:), g_Scell(SCN)%MDAtoms(i)%S(:)
      !write(6,'(i3,f,f,f,f,f,f)') i, MDAtoms(i)%S0(:), MDAtoms(i)%S(:) 
   enddo
   supce0 = g_Scell(1)%supce0 
   supce = g_Scell(1)%supce
   Vsupce0 = g_Scell(1)%Vsupce0
   Vsupce = g_Scell(1)%Vsupce
   
   N_steps = 100
   
   do i_step = 1, N_steps+1
      i = i_step
      sc_fact = dble(i_step-1)/dble(N_steps)
      g_time = sc_fact
!       write(6,'(a,f)') 'Step:', g_time
      
      ! set coordinates and supercell:
      g_Scell(1)%supce = supce0 - (supce0 - supce) * sc_fact
      g_Scell(SCN)%Vsupce = Vsupce0 - (Vsupce0 - Vsupce) * sc_fact
      do i_at = 1, Nat
            g_Scell(SCN)%MDAtoms(i_at)%S0(:) = MDAtoms(i_at)%S0(:) + (MDAtoms(i_at)%S(:) - MDAtoms(i_at)%S0(:)) * sc_fact
            g_Scell(SCN)%MDAtoms(i_at)%SV0(:) = MDAtoms(i_at)%SV0(:) + (MDAtoms(i_at)%SV0(:) - MDAtoms(i_at)%SV0(:)) * sc_fact
            g_Scell(SCN)%MDAtoms(i_at)%S(:) = MDAtoms(i_at)%S0(:) + (MDAtoms(i_at)%S(:) - MDAtoms(i_at)%S0(:)) * sc_fact
            g_Scell(SCN)%MDAtoms(i_at)%SV(:) = MDAtoms(i_at)%SV0(:) + (MDAtoms(i_at)%SV(:) - MDAtoms(i_at)%SV0(:)) * sc_fact
      enddo
      call Coordinates_rel_to_abs(g_Scell, SCN, if_old=.true.)	! from the module "Atomic_tools"
      call velocities_abs_to_rel(g_Scell, SCN, if_old=.true.)	! from the module "Atomic_tools"
      
      ! Contruct TB Hamiltonian, diagonalize to get energy levels, get forces for atoms and supercell:
      call get_Hamilonian_and_E(g_Scell, g_numpar, g_matter, 1, g_Err, g_time) ! module "TB"

      ! Get global energy of the system at the beginning:
      call get_glob_energy(g_Scell, g_matter) ! module "Electron_tools"

!        write(100,'(es25.16,es25.16,es25.16,es25.16)') g_time, g_Scell(1)%nrg%Total+g_Scell(1)%nrg%E_supce+g_Scell(1)%nrg%El_high+g_Scell(1)%nrg%Eh_tot+g_Scell(1)%nrg%E_vdW, g_Scell(1)%nrg%E_rep, g_Scell(1)%nrg%El_low
       
       call write_energies(6, g_time, g_Scell(1)%nrg)   ! module "Dealing_with_output_files"
       call write_energies(100, g_time, g_Scell(1)%nrg)   ! module "Dealing_with_output_files"
       call get_electronic_thermal_parameters(g_numpar, g_Scell, 1, g_matter, g_Err) ! module "TB"

       ! Save initial step in output:
       call write_output_files(g_numpar, g_time, g_matter, g_Scell) ! module "Dealing_with_output_files"
       
       call print_time_step('Coordinate path point:', g_time, msec=.true.)   ! module "Little_subroutines"
       
   enddo
   
   close(100)
   write(6, '(a)') 'Subroutine coordinate_path completed, file OUTPUT_coordinate_path.dat is created'
   write(6, '(a)') 'XTANT is terminating now...'
   g_Err%Err = .true.   ! not to continue with the real calculations
end subroutine coordinate_path
 
 
 
!TTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTT
! Use this for testing and finding potential energy minimum as a function of supercell size:
subroutine vary_size(do_forces, Err)
   integer, optional, intent(in) :: do_forces
   logical, intent(out), optional :: Err
   real(8) :: r_sh, x, y, z, E_vdW_interplane, g_time_save, z_sh, z_sh0, temp, E_ZBL
   integer i, j, at1, at2
   character(13) :: char1
   logical yesno
   open(UNIT = 100, FILE = 'OUTPUT_Energy.dat')
   if (present(do_forces)) then
      write(100,'(a)') '#Distance   E_total  E_rep El_low   F_rep F_att'
   else
      write(100,'(a)') '#Distance   E_total  E_rep El_low   E_vdW E_ZBL Z_size'
   endif

   g_time_save = g_time
   z_sh0 = 0.0d0
   
   !----------------------------------------------
!    ! Project-specific (Graphene on SiC), removing graphene from substrate:
!    z_sh = -0.05d0 + dble(i_test)/5000.0d0
!    temp = maxval(g_Scell(1)%MDatoms(:)%S(3))
!    do i = 1,size(g_Scell(1)%MDatoms) ! find the nearest neighbour
!       if (g_Scell(1)%MDatoms(i)%S(3) == temp) then
!          call Shift_all_atoms(g_matter, g_Scell, 1, shz=z_sh0-z_sh, N_start=i, N_end=i) ! above
!          print*, 'ATOM #', i, g_Scell(1)%MDatoms(i)%S(:)
!       endif
!    enddo
!    !----------------------------------------------
   
   do i_test = 1,300 !<-
      !----------------------------------------------
      ! General feature, changing size:
      
       g_Scell(1)%supce = g_Scell(1)%supce0*(0.7d0 + dble(i_test)/200.0d0) !<-
      
!       print*, 'g_Scell0', g_Scell(1)%supce0
!       print*, 'g_Scell', g_Scell(1)%supce
!       pause 'CELL'
      
      !----------------------------------------------
      ! Project-specific (C60 crystal), shifting one C60 ball relative to the other:
!        z_sh = -0.05d0 + dble(i_test)/5000.0d0
!        call Shift_all_atoms(g_matter, g_Scell, 1, shz=z_sh0-z_sh, N_start=61, N_end=120) ! above
!        print*, 'Z=', z_sh, g_Scell(1)%MDatoms(1)%S(3), g_Scell(1)%MDatoms(31)%S(3), g_Scell(1)%MDatoms(91)%S(3)
!        z_sh0 = z_sh
      !----------------------------------------------
      ! Project-specific (Graphene on SiC), removing graphene from substrate:
!       z_sh = -0.02d0 + dble(i_test)/5000.0d0
!       temp = maxval(g_Scell(1)%MDatoms(:)%S(3))
!       do i = 1,size(g_Scell(1)%MDatoms) ! find the nearest neighbour
!          if (g_Scell(1)%MDatoms(i)%S(3) == temp) then
!             call Shift_all_atoms(g_matter, g_Scell, 1, shz=z_sh0-z_sh, N_start=i, N_end=i) ! above
!             print*, 'ATOM #', i, g_Scell(1)%MDatoms(i)%S(:)
!          endif
!       enddo
!       z_sh0 = z_sh
!       !----------------------------------------------

      call Det_3x3(g_Scell(1)%supce,g_Scell(1)%V) !<- modlue "Algebra_tools"

      call Coordinates_rel_to_abs(g_Scell, 1, if_old=.true.)	! from the module "Atomic_tools"!<-
      
      g_time = 1d9   ! to start with
      r_sh = 1d10    ! to start with
      at1 = 1  ! to start with
      at2 = 2  ! to start with
      do j = 1,size(g_Scell(1)%MDatoms)-1 ! find the nearest neighbour
         do i = j+1,size(g_Scell(1)%MDatoms) ! find the nearest neighbour
            call shortest_distance(g_Scell, 1, g_Scell(1)%MDatoms, j, i, r_sh) ! module 'Atomic_tools'
            if (g_time > r_sh) then
               g_time = r_sh ! [A] nearest neighbor distance
               at1 = j
               at2 = i
            endif
         enddo
      enddo
      !call change_r_cut_TB_Hamiltonian(1.70d0*(g_Scell(1)%supce(3,3)*0.25d0)/1.3d0, TB_Waals=g_Scell(1)%TB_Waals) !<-

      ! Contruct TB Hamiltonian, diagonalize to get energy levels, get forces for atoms and supercell:
      call get_Hamilonian_and_E(g_Scell, g_numpar, g_matter, 1, g_Err, g_time) ! module "TB"
      if (g_numpar%verbose) call print_time_step('Hamiltonian constructed and diagonalized', msec=.true.)

      ! Get global energy of the system at the beginning:
      call get_glob_energy(g_Scell, g_matter) ! module "Electron_tools"

      ! Get initial optical coefficients:
      call get_optical_parameters(g_numpar, g_matter, g_Scell, g_Err) ! module "Optical_parameters"
      
      ! Get initial DOS:
      call get_DOS(g_numpar, g_matter, g_Scell, g_Err)	! module "TB"

      call get_Mulliken(g_numpar%Mulliken_model, g_numpar%mask_DOS, g_numpar%DOS_weights, g_Scell(1)%Ha, &
                            g_Scell(1)%fe, g_matter, g_Scell(1)%MDAtoms, g_matter%Atoms(:)%mulliken_Ne) ! module "TB"
      call get_electronic_thermal_parameters(g_numpar, g_Scell, 1, g_matter, g_Err) ! module "TB"

      ! Save initial step in output:
      call write_output_files(g_numpar, g_time, g_matter, g_Scell) ! module "Dealing_with_output_files"

      ! Get interplane energy for vdW potential:
      E_vdW_interplane = vdW_interplane(g_Scell(1)%TB_Waals, g_Scell, 1, g_numpar, g_matter)/dble(g_Scell(1)%Na) !module "TB"

      ! Get ZBL potential is requested:
      call get_total_ZBL(g_Scell, 1, g_matter, E_ZBL) ! module "ZBL_potential"
      E_ZBL = E_ZBL/dble(g_Scell(1)%Na)   ! [eV] => [eV/atom]

      if (present(do_forces)) then
         print*, 'Supercell size:', i_test, &
         trim(adjustl(g_matter%Atoms(g_Scell(1)%MDAtoms(at1)%KOA)%Name))//'-'// &
         trim(adjustl(g_matter%Atoms(g_Scell(1)%MDAtoms(at2)%KOA)%Name)) , g_time, &
         g_Scell(1)%nrg%Total+g_Scell(1)%nrg%E_supce+g_Scell(1)%nrg%El_high+g_Scell(1)%nrg%Eh_tot+g_Scell(1)%nrg%E_vdW
         write(100,'(es25.16,es25.16,es25.16,es25.16,es25.16,es25.16,es25.16,es25.16,es25.16,es25.16)') &
               g_time, g_Scell(1)%nrg%Total+g_Scell(1)%nrg%E_supce+g_Scell(1)%nrg%El_high+g_Scell(1)%nrg%Eh_tot+g_Scell(1)%nrg%E_vdW, &
               g_Scell(1)%nrg%E_rep, g_Scell(1)%nrg%El_low, g_Scell(1)%MDatoms(do_forces)%forces%rep(:), &
               g_Scell(1)%MDatoms(do_forces)%forces%att(:)
      else
         print*, 'Supercell size:', i_test, &
         trim(adjustl(g_matter%Atoms(g_Scell(1)%MDAtoms(at1)%KOA)%Name))//'-'// &
         trim(adjustl(g_matter%Atoms(g_Scell(1)%MDAtoms(at2)%KOA)%Name)), at1, at2, g_time, &
         g_Scell(1)%nrg%Total+g_Scell(1)%nrg%E_supce+g_Scell(1)%nrg%El_high+g_Scell(1)%nrg%Eh_tot+g_Scell(1)%nrg%E_vdW
         write(100,'(es25.16,es25.16,es25.16,es25.16,es25.16,es25.16,es25.16)') g_time, &
               g_Scell(1)%nrg%Total+g_Scell(1)%nrg%E_supce+g_Scell(1)%nrg%El_high+g_Scell(1)%nrg%Eh_tot+g_Scell(1)%nrg%E_vdW, &
               g_Scell(1)%nrg%E_rep, g_Scell(1)%nrg%El_low, E_vdW_interplane, E_ZBL, g_Scell(1)%supce(3,3)
      endif
   enddo
   g_time = g_time_save
   g_Scell(1)%supce = g_Scell(1)%supce0

   ! Uncomment here if you want to be able to proceed with regular calculations after "size",
   ! this option has never been used, so now by default it is depricated.
!    write(*,'(a)') '*************************************************************'
!    print*, ' Would you like to proceed with XTANT calculation? (y/n)',char(13)
!    read(*,*) char1
   write(*,'(a)') '*************************************************************'
   char1 = 'n' ! by default, stop calculations here
   call parse_yes_no(trim(adjustl(char1)), yesno) ! Little_subroutines
   Err = .not.yesno
end subroutine vary_size


END PROGRAM XTANT

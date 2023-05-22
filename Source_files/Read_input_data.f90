! 000000000000000000000000000000000000000000000000000000000000
! This file is part of XTANT
!
! Copyright (C) 2016-2023 Nikita Medvedev
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
!
! 1111111111111111111111111111111111111111111111111111111111111
! This module contains subroutines to read input files:

MODULE Read_input_data
use Objects
use Universal_constants
!use Variables
use Little_subroutines, only : print_time_step
use Dealing_with_files, only : Path_separator, Count_lines_in_file, close_file, copy_file, read_file
use Dealing_with_EADL, only : m_EADL_file, m_EPDL_file, READ_EADL_TYPE_FILE_int, READ_EADL_TYPE_FILE_real, select_imin_imax
use Dealing_with_DFTB, only : m_DFTB_directory, construct_skf_filename, read_skf_file, same_or_different_atom_types, &
                           idnetify_basis_size, m_DFTB_norep_directory, read_skf_file_no_rep
use Dealing_with_BOP, only : m_BOP_directory, m_BOP_file, read_BOP_parameters, idnetify_basis_size_BOP, &
                            read_BOP_repulsive, check_if_repulsion_exists
use Dealing_with_3TB, only : m_3TB_directory, m_3TB_onsite_data, read_3TB_onsite_file , construct_3TB_filenames, &
                            read_3TB_2bdy_file, read_3TB_3bdy_file
use Dealing_with_xTB, only : m_xTB_directory, read_xTB_parameters, identify_basis_size_xTB, identify_AOs_xTB
use Periodic_table, only : Decompose_compound

! Open_MP related modules from external libraries:
#ifdef OMP_inside
   USE IFLPORT, only : system
   USE OMP_LIB, only : omp_get_max_threads
#endif

implicit none
PRIVATE


! Modular parameters:
character(25) :: m_INPUT_directory, m_INPUT_MATERIAL, m_NUMERICAL_PARAMETERS, m_Atomic_parameters, m_Hubbard_U
character(70), parameter :: m_starline = '*************************************************************'

character(15), parameter :: m_INFO_directory = 'INFO'  ! folder with the help-texts
character(15), parameter :: m_INFO_file = 'INFO.txt'  ! file with some XTANT info
character(15), parameter :: m_HELP_file = 'HELP.txt'  ! file with the helpful info
character(25), parameter :: m_List_ofmaterials = 'List_of_materials.txt'  ! list of materials existing

parameter (m_INPUT_directory = 'INPUT_DATA')
parameter (m_INPUT_MATERIAL = 'INPUT_MATERIAL')
parameter (m_NUMERICAL_PARAMETERS = 'NUMERICAL_PARAMETERS')
parameter (m_Atomic_parameters = 'Atomic_parameters')
parameter (m_Hubbard_U = 'INPUT_Hubbard_U.dat')


public :: m_INPUT_directory, m_INPUT_MATERIAL, m_NUMERICAL_PARAMETERS, m_Atomic_parameters, m_Hubbard_U
public :: m_INFO_directory, m_INFO_file, m_HELP_file, m_starline

public :: Read_Input_Files, get_add_data

 contains


! These values will be used, unles changed by the user or in the input file:
subroutine initialize_default_values(matter, numpar, laser, Scell)
   type(Solid), intent(inout) :: matter	! all material parameters
   type(Numerics_param), intent(inout) :: numpar 	! all numerical parameters
   type(Pulse), dimension(:), allocatable, intent(inout) :: laser	! Laser pulse parameters
   type(Super_cell), dimension(:), allocatable, intent(inout) :: Scell ! suoer-cell with all the atoms inside
   !----------------------------------------------
   integer :: N
   ! Here we set default values, in case some of them are not given by the user:
   matter%Name = '' ! Material name
   matter%Chem = '' ! chemical formula of the compound
   if (.not.allocated(Scell)) allocate(Scell(1)) ! So far we only use 1 supercell
   numpar%lin_scal = 0   ! do not use linear scaling TB
   Scell(1)%Te = 300.0d0 ! initial electron temperature [K]
   Scell(1)%TeeV = Scell(1)%Te/g_kb ! [eV] electron temperature
   Scell(1)%Ta = 300.0d0 ! initial atomic temperature [K]
   Scell(1)%TaeV = Scell(1)%Ta/g_kb ! [eV] atomic temperature
   numpar%t_total = 1000.0d0 ! total duration of simulation [fs]
   call initialize_default_laser(laser, 1) ! initialize 1 pulse by default
   numpar%optic_model = 0 ! no optical calculations by default
   numpar%do_drude = .false.	! excluded optical calculations
   Scell(1)%eps%all_w = .false.	! excluded spectral calculations
   Scell(1)%eps%KK = .false.	! do not use Kramers Kronig relation
   Scell(1)%eps%E_min = 0.05d0 ! starting point of the grid of energy [eV]
   Scell(1)%eps%E_max = 50.0d0 ! ending point of the grid of energy [eV]
   Scell(1)%eps%dE = 0.1d0    ! grid step of energy [eV]
   numpar%drude_ray = 0	! Absorbtion of how many rays (0=exclude, 1=1st ray, (>1)=sum all)
   Scell(1)%eps%l = 800.0d0	! probe-pulse wavelength [nm]
   Scell(1)%eps%tau = -10.0d0	! probe duration FWHM [fs]
   Scell(1)%eps%ReEps0 = 0.0d0	! to start with
   Scell(1)%eps%ImEps0 = 0.0d0	! to start with
   Scell(1)%eps%w = 2.0d0*g_Pi*g_cvel/(Scell(1)%eps%l*1d-9) ! [1/sec] frequency
   Scell(1)%eps%teta = 0.0d0	! Angle of prob-pulse with respect to normal [degrees]
   Scell(1)%eps%teta = Scell(1)%eps%teta*g_Pi/(180.0d0) !c [radians]
   Scell(1)%eps%dd = 100.0d0	! material thickness [nm]
   ! number of unit-cells in X,Y,Z: 
   matter%cell_x = 1
   matter%cell_y = 1
   matter%cell_z = 1
   numpar%At_base = 'EADL' ! where to take atomic data from (EADL, CDF, etc...)
   matter%dens = -1.0d0 ! [g/cm^3] density of the material (negative = use MD supercell to evaluate it)
   numpar%NMC = 30000	! number of iterations in the MC module
#ifdef OMP_inside
   numpar%NOMP = omp_get_max_threads()	! number of processors available by default
#else ! if you set to use OpenMP in compiling: 'make OMP=no'
   numpar%NOMP = 1	! unparallelized by default
#endif
   numpar%N_basis_size = 0  ! DFTB, BOP or 3TB basis set default (0=s, 1=sp3, 2=sp3d5)
   numpar%do_atoms = .true.	! Atoms are allowed to move
   matter%W_PR = 25.5d0  ! Parinello-Rahman super-vell mass coefficient
   numpar%dt = 0.01d0 	! Time step for MD [fs]
   numpar%halfdt = numpar%dt/2.0d0      ! dt/2, often used
   numpar%dtsqare = numpar%dt*numpar%halfdt ! dt*dt/2, often used
   numpar%dt3 = numpar%dt**3/6.0d0            ! dt^3/6, often used
   numpar%dt4 = numpar%dt*numpar%dt3/8.0d0    ! dt^4/48, often used
   numpar%MD_algo = 0       ! 0=Verlet (2d order); 1=Yoshida (4th order)
   numpar%dt_save = 1.0d0	! save data into files every [fs]
   numpar%p_const = .false.	! V=const
   matter%p_ext = g_P_atm	! External pressure [Pa] (0 = normal atmospheric pressure)
   numpar%el_ion_scheme = 0	! scheme (0=decoupled electrons; 1=enforced energy conservation; 2=T=const; 3=BO)
   numpar%t_Te_Ee = 1.0d-3	! when to start coupling
   numpar%NA_kind = 1	! 0=no coupling, 1=dynamical coupling (2=Fermi-golden_rule)
   numpar%Nonadiabat = .true.  ! included
   numpar%tau_fe = 1.0d0   ! Characteristic electron relaxation time [fs]
   numpar%scc = .true.  ! included
   numpar%scc_gam_ind = 0  ! Wolf's Coulomb model
   numpar%scc_mix = 1.0d0  ! maximal mixing
   numpar%t_NA = 1.0d-3	! [fs] start of the nonadiabatic
   numpar%acc_window = 5.0d0	! [eV] acceptance window for nonadiabatic coupling:
   numpar%do_kappa = .false.  ! electron heat conductivity calculation
   numpar%do_cool = .false.	! quenching excluded
   numpar%at_cool_start = 2500.0	! starting from when [fs]
   numpar%at_cool_dt = 40.0	! how often [fs]
   numpar%Transport = .false. ! excluded heat transport
   matter%T_bath = 300.0d0	! [K] bath temperature for atoms
   matter%T_bath = matter%T_bath/g_kb	! [eV] thermostat temperature
   matter%T_bath_e = 300.0d0	! [K] bath temperature for electrons
   matter%T_bath_e = matter%T_bath_e/g_kb	! [eV] thermostat temperature
   matter%tau_bath = 300.0d0	! [fs] time constant of cooling for atoms
   matter%tau_bath_e = 300.0d0	! [fs] time constant of cooling for electrons
   numpar%E_cut = 10.0d0 ! [eV] cut-off energy for high
   numpar%E_cut_dynamic = .false. ! do not change E_cut
   numpar%E_work = 1.0d30 ! [eV] work function (exclude electron emission)
   numpar%E_Coulomb = 0.0d0 ! [eV] Coulomb attraction of electrons back to the material
   numpar%save_Ei = .false.	! excluded printout energy levels (band structure)
   numpar%save_DOS = .false.	! excluded calculation and printout of DOS
   numpar%Smear_DOS = 0.05d0	! [eV] default smearing for DOS calculations
   numpar%save_fe = .false.	! excluded printout distribution function
   numpar%save_fe_grid = .false.	! excluded printout distribution function on the grid
   numpar%save_PCF = .false.	! excluded printout pair correlation function
   numpar%save_XYZ = .true.	! included printout atomic coordinates in XYZ format
   numpar%save_CIF = .true.	! included printout atomic coordinates in CIF format
   numpar%save_raw = .true.	! included printout of raw data for atomic coordinates, relative coordinates, velocities
   numpar%NN_radius = 0.0d0 ! radius of nearest neighbors defined by the user [A]
   numpar%MSD_power = 1     ! by default, print out mean displacement [A^1]
   numpar%save_NN = .false. ! do not print out nearest neighbors numbers
   numpar%do_elastic_MC = .true. ! allow elastic scattering of electrons on atoms within MC module
   numpar%r_periodic(:) = .true. ! use periodic boundaries along each direction of the simulation box
   ! Setting supercell for biomolecules, embedding in water:
   numpar%embed_water = .false.  ! no water added
   numpar%N_water_mol = 100      ! default number of water molecules
   ! number of k-points in each direction (used only for Trani-k!):
   numpar%ixm = 1
   numpar%iym = 1
   numpar%izm = 1
   ! BOP parameters:
   numpar%create_BOP_repulse = .false.
   ! initial n and k of unexcited material (used for DRUDE model only!):
   Scell(1)%eps%n = 1.0d0
   Scell(1)%eps%k = 0.0d0
   ! [me] effective mass of CB electron and VB hole:
   Scell(1)%eps%me_eff = 1.0d0
   Scell(1)%eps%mh_eff = 1.0d0
   Scell(1)%eps%me_eff = Scell(1)%eps%me_eff*g_me	! [kg]
   Scell(1)%eps%mh_eff = Scell(1)%eps%mh_eff*g_me	! [kg]
   ! [fs] mean scattering times of electrons and holes:
   Scell(1)%eps%tau_e = 1.0d0
   Scell(1)%eps%tau_h = 1.0d0
end subroutine initialize_default_values


subroutine initialize_default_laser(laser, N)
   type(Pulse), dimension(:), allocatable, intent(inout) :: laser	! Laser pulse parameters
   integer, intent(in) :: N	! how many pulses
   integer i
   
   if (.not.allocated(laser)) then
      allocate(laser(N))
   else if (size(laser) /= N) then
      deallocate(laser)
      allocate(laser(N))
   endif
   
   do i = 1,N
      call initialize_default_single_laser(laser, i)
   enddo
end subroutine initialize_default_laser


subroutine initialize_default_single_laser(laser, i) ! Must be already allocated
   type(Pulse), dimension(:), allocatable, intent(inout) :: laser	! Laser pulse parameters
   integer, intent(in) :: i	! number of the pulse
   laser(i)%F = 0.0d0  ! ABSORBED DOSE IN [eV/atom]
   laser(i)%hw = 100.0d0  ! PHOTON ENERGY IN [eV]
   laser(i)%FWHM_hw = 0.0d0  ! distribution of photon energies [eV]
   laser(i)%t = 10.0d0	  ! PULSE FWHM-DURATION IN
   laser(i)%KOP = 1  	  ! type of pulse: 0=rectangular, 1=Gaussian, 2=SASE
   !laser(i)%t = laser(i)%t/2.35482	! make a gaussian parameter out of it
   laser(i)%t0 = 0.0d0	  ! POSITION OF THE MAXIMUM OF THE PULSE IN [fs]
end subroutine initialize_default_single_laser


subroutine extend_laser(laser, N_extend)
   type(Pulse), dimension(:), allocatable, intent(inout) :: laser	! Laser pulse parameters
   integer, intent(in), optional :: N_extend	! extend the array by this many elements
   !----------------------------
   type(Pulse), dimension(:), allocatable :: temp_laser
   integer :: i, N, add_N
   if (present(N_extend)) then
      add_N = N_extend	! specified extension value
   else
      add_N = 1	! by default, extend the array by 1
   endif
   
   if (.not.allocated(laser)) then 	! it's first time, no parameters given in laser
      allocate(laser(add_N)) 	! just allocate it
      do i = 1, add_N		! and set all default parameters
         call initialize_default_single_laser(laser, i)
      enddo
   else	! there are already parameters for some of the pulses
      N = size(laser)	! number of those pulses were N, they need to be saved
      allocate(temp_laser(N))	! they are saved in a temporary array
      temp_laser = laser	! save them here
      deallocate(laser)		! now we need to extend the dimension: deallocate it first
      allocate(laser(N+add_N))	! and reallocate with the new size
      laser(1:N) = temp_laser(1:N)	! get all the previous data back into their positions
      deallocate(temp_laser)	! free the memory from the temporary array
      do i = N, N+add_N		! set all default parameters for the new elements
         call initialize_default_single_laser(laser, i)
      enddo
   endif
end subroutine extend_laser



!subroutine Read_Input_Files(matter, numpar, laser, TB_Repuls, TB_Hamil, Err)
subroutine Read_Input_Files(matter, numpar, laser, Scell, Err, Numb)
   type(Solid), intent(out) :: matter	! all material parameters
   type(Numerics_param), intent(inout) :: numpar 	! all numerical parameters
   type(Pulse), dimension(:), allocatable, intent(out) :: laser	! Laser pulse parameters
   type(Super_cell), dimension(:), allocatable, intent(inout) :: Scell ! suoer-cell with all the atoms inside
   ! For polymorphic variables:
!    class(TB_repulsive), dimension(:), allocatable, intent(out) :: TB_Repuls  ! parameters of the repulsive part of TB
!    class(TB_Hamiltonian), dimension(:), allocatable, intent(out) ::  TB_Hamil ! parameters of the Hamiltonian of TB
   type(Error_handling), intent(inout) :: Err	! error save
   integer, intent(in), optional :: Numb ! number of input files to use
   !-----------------------------
   type(User_overwrite_data) :: user_data
   real(8) temp
   integer FN, Reason, count_lines, N, i
   logical file_exist, file_opened, read_well
   character(100) Error_descript, Folder_name, File_name
   character(3) chnum
   
   !--------------------------------------------------------------------------
   ! In case the user didn't define something, the default values will be used
   ! So, the user does not have to define everything every time. 
   ! Set default values:
   call initialize_default_values(matter, numpar, laser, Scell)
   !--------------------------------------------------------------------------
   ! Now, read the input file:
   call Path_separator(numpar%path_sep) ! module "Dealing_with_files"
   !Folder_name = 'INPUT_DATA'//numpar%path_sep
   Folder_name = trim(adjustl(m_INPUT_directory))//numpar%path_sep
   numpar%input_path = Folder_name ! save the address with input files

   ! New input file format:
   if (.not.present(Numb)) then ! first run, use default files:
      File_name = trim(adjustl(Folder_name))//'INPUT.txt'
   else ! it's not the first run, use next set of parameters:
      File_name = trim(adjustl(Folder_name))//'INPUT'
      write(chnum,'(i3)') Numb
      write(File_name,'(a,a,a,a)') trim(adjustl(File_name)), '_', trim(adjustl(chnum)), '.txt'
   endif
   inquire(file=trim(adjustl(File_name)),exist=file_exist)
   
   NEW_FORMAT:if (file_exist) then ! read parameters from the new file format
      call read_input_txt(File_name, Scell, matter, numpar, laser, Err) ! see above
      if (Err%Err) goto 3416
   else NEW_FORMAT ! Then use old format of two files
      ! First read material and pulse parameters:
      if (.not.present(Numb)) then ! first run, use default files:
         !File_name = trim(adjustl(Folder_name))//'INPUT_MATERIAL.txt'
         File_name = trim(adjustl(Folder_name))//trim(adjustl(m_INPUT_MATERIAL))//'.txt'
      else ! it's not the first run, use next set of parameters:
         !File_name = trim(adjustl(Folder_name))//'INPUT_MATERIAL'
         File_name = trim(adjustl(Folder_name))//trim(adjustl(m_INPUT_MATERIAL))
         write(chnum,'(i3)') Numb
         write(File_name,'(a,a,a,a)') trim(adjustl(File_name)), '_', trim(adjustl(chnum)), '.txt'
      endif
      inquire(file=trim(adjustl(File_name)),exist=file_exist)
      INPUT_MATERIAL:if (file_exist) then
         call read_input_material(File_name, Scell, matter, numpar, laser, Err) ! see below
         if (Err%Err) goto 3416
      else
         write(Error_descript,'(a,$)') 'File '//trim(adjustl(File_name))//' could not be found, the program terminates'
         call Save_error_details(Err, 1, Error_descript)
         print*, trim(adjustl(Error_descript))
         goto 3416
      endif INPUT_MATERIAL


      ! Read numerical parameters:
      if (.not.present(Numb)) then ! first run, use default files:
         !File_name = trim(adjustl(Folder_name))//'NUMERICAL_PARAMETERS.txt'
         File_name = trim(adjustl(Folder_name))//trim(adjustl(m_NUMERICAL_PARAMETERS))//'.txt'
      else ! it's not the first run, use next set of parameters:
         !File_name = trim(adjustl(Folder_name))//'NUMERICAL_PARAMETERS'
         File_name = trim(adjustl(Folder_name))//trim(adjustl(m_NUMERICAL_PARAMETERS))
         write(chnum,'(i3)') Numb
         write(File_name,'(a,a,a,a)') trim(adjustl(File_name)), '_', trim(adjustl(chnum)), '.txt'
      endif
      inquire(file=trim(adjustl(File_name)),exist=file_exist)
      ! Maybe reuse the default one, if identical parameters are to be used:
      if (.not.file_exist) then
         File_name = trim(adjustl(Folder_name))//trim(adjustl(m_NUMERICAL_PARAMETERS))//'.txt'
         inquire(file=trim(adjustl(File_name)),exist=file_exist)
      endif

      NUMERICAL_PARAMETERS:if (file_exist) then
         call read_numerical_parameters(File_name, matter, numpar, laser, Scell, user_data, Err) ! see below
         if (Err%Err) goto 3416
      else
         write(Error_descript,'(a,$)') 'File '//trim(adjustl(File_name))//' could not be found, the program terminates'
         call Save_error_details(Err, 1, Error_descript)
         print*, trim(adjustl(Error_descript))
         goto 3416
      endif NUMERICAL_PARAMETERS
   endif NEW_FORMAT

   ! Check if the molecule needs to be embedded in water (as requested in input file):
   if (numpar%embed_water) then
      call add_water_to_chemical_formulae(matter, numpar)   ! below
   endif

   if (.not.allocated(Scell)) allocate(Scell(1)) ! for the moment, only one super-cell

   ! Do TB and MD part only if we want (supercell is larger than 0):
   do i = 1, size(Scell)
      ! Read atomic data:
      call read_atomic_parameters(matter, numpar, Err) ! below
      Scell(i)%E_gap = matter%Atoms(1)%Ip(size(matter%Atoms(1)%Ip))	! [eV] band gap at the beginning
      Scell(i)%N_Egap = -1	! just to start with something
      ! Read TB parameters:
      if (matter%cell_x*matter%cell_y*matter%cell_z .GT. 0) then
         call read_TB_parameters(matter, numpar, Scell(i)%TB_Repuls, Scell(i)%TB_Hamil, &
                           Scell(i)%TB_Waals, Scell(i)%TB_Coul, Scell(i)%TB_Expwall, Err) ! below
      else ! do only MC part
          ! Run it like XCASCADE
      endif
   enddo

   ! Check if the user provided atomic data to overwrite the default values:
   call overwrite_atomic_data(user_data, matter)   ! below

   ! Atomic density [1/cm^3] (may be overwritten in the module "Initial_configuration", if negative):
   matter%At_dens = matter%dens/(SUM(matter%Atoms(:)%Ma*matter%Atoms(:)%percentage)/(SUM(matter%Atoms(:)%percentage))*1d3)


   ! Check k-space grid file:
   call read_k_grid(matter, numpar, Err)	! below

   ! Read Hubbard U parameter for self-consistent charge (SCC), if requested:
   if (numpar%scc) then
      ! Get file with Hubbard parameter:
      File_name = trim(adjustl(Folder_name))//trim(adjustl(m_Atomic_parameters))//numpar%path_sep//trim(adjustl(m_Hubbard_U))
      inquire(file=trim(adjustl(File_name)),exist=file_exist)
      if (file_exist) then
         call read_SCC_Hubbard(File_name, matter, numpar%scc)  ! below
      else  ! if there is no Hubbard parameters file, cannot use SCC:
         print*, 'File '//trim(adjustl(File_name))//' not found, SCC cannot be used'
         numpar%scc = .false.
      endif

      ! Consistency check:
      if (size(matter%Atoms) < 2) then ! no need for self-consistent charge calculations
         numpar%scc = .false.
         print*, 'SCC: Self-consistent change calculations for elemental solids are excluded'
      else
         if (numpar%scc_mix < 0.1d0) numpar%scc_mix = 0.1d0
         if (numpar%scc_mix > 1.0d0) numpar%scc_mix = 1.0d0
      endif
   endif

3416 continue !exit in case if input files could not be read
end subroutine Read_Input_Files



subroutine add_water_to_chemical_formulae(matter, numpar)   ! below
   type(Solid), intent(inout) :: matter   ! all material parameters
   type(Numerics_param), intent(in) :: numpar 	! all numerical parameters
   !-----------------------------
   character(200) :: Folder_name, error_message
   character(100) :: chem_form, temp
   character(3) :: atom_elem
   integer :: N_at, i_H, i_O, INFO, i, N_SC
   integer, dimension(:), allocatable :: at_numbers
   real(8), dimension(:), allocatable :: at_percentage
   character(3), dimension(:), allocatable :: at_short_names ! name of the element
   logical :: H_exists, O_exists

!     print*, 'Chemical formula old: ', trim(adjustl(matter%Chem))

   ! Check if the atoms from the water molecule are already present:
   chem_form = trim(adjustl(matter%Chem)) ! save chemical formula
   Folder_name = trim(adjustl(numpar%input_path))//trim(adjustl(m_Atomic_parameters))   !'Atomic_parameters'

   call Decompose_compound(Folder_name, chem_form, numpar%path_sep, INFO, error_message, matter%N_KAO, at_numbers, at_percentage, at_short_names) ! molude 'Periodic_table'

   if (INFO == 0) then
      H_exists = .false.   ! to start with
      O_exists = .false.   ! to start with

      N_SC = INT(matter%cell_x*matter%cell_y*matter%cell_z) ! number of molecules in the supercell
      matter%Chem = ''  ! to start with
      do i = 1, size(at_short_names)
         if (trim(adjustl(at_short_names(i))) == 'H') then
            ! That's how many hyhdrogens there are in total (molecule + water):
            write(temp,'(i6)') INT(at_percentage(i))*N_SC + numpar%N_water_mol*2
            matter%Chem = trim(adjustl(matter%Chem))//'H'//trim(adjustl(temp))
            H_exists = .true. ! found it, added into the chemical formula
         elseif (trim(adjustl(at_short_names(i))) == 'O') then
            ! That's how many oxygens there are in total (molecule + water):
            write(temp,'(i6)') INT(at_percentage(i))*N_SC + numpar%N_water_mol
            matter%Chem = trim(adjustl(matter%Chem))//'O'//trim(adjustl(temp))
            O_exists = .true. ! found it, added into the chemical formula
         else  ! all other elements just write back as they are (x number of unit cells)
            write(temp,'(i6)') INT(at_percentage(i))*N_SC
            matter%Chem = trim(adjustl(matter%Chem))//trim(adjustl(at_short_names(i)))//trim(adjustl(temp))
         endif
      enddo
      ! Add at the end H or O, if they were not in the formula:
      if (.not.H_exists) then
         write(temp,'(i6)') numpar%N_water_mol*2
         matter%Chem = trim(adjustl(matter%Chem))//'H'//trim(adjustl(temp))
      endif
      if (.not.O_exists) then
         write(temp,'(i6)') numpar%N_water_mol
         matter%Chem = trim(adjustl(matter%Chem))//'O'//trim(adjustl(temp))
      endif
   endif ! (INFO .NE. 0)
!     print*, 'Chemical formula new: ', trim(adjustl(matter%Chem))
!     pause 'Chem done'
end subroutine add_water_to_chemical_formulae



subroutine read_SCC_Hubbard(File_name, matter, SCC)
   character(*), intent(in) :: File_name  ! file with Hubbard parameters
   type(Solid), intent(inout) :: matter   ! all material parameters
   logical, intent(inout) :: SCC ! flag to use SCC or not
   !---------------------------
   real(8) :: U_read
   integer :: TOA, i, j, FN, count_lines, Reason
   logical :: file_opened, read_well, found_el
   character(3) :: El_name

   FN = 103
   open(UNIT=FN, FILE = trim(adjustl(File_name)), status = 'old', action='read')
   inquire(file=trim(adjustl(File_name)),opened=file_opened)
   if (.not.file_opened) then
      print*, 'File '//trim(adjustl(File_name))//' could not be opened, SCC cannot be used'
      SCC = .false.
      goto 3430
   endif

   RF:do i = 1, size(matter%Atoms) ! for all types of atoms
      found_el = .false.
      count_lines = 0   ! to start with
      read(FN,*,IOSTAT=Reason) ! skip first two lines with comments
      call read_file(Reason, count_lines, read_well)
      if (.not. read_well) then
         print*, 'Could not read line ', count_lines, ' in file '//trim(adjustl(File_name))
         print*, 'SCC cannot be used, proceeding at non-self-consistent level'
         SCC = .false.
         exit RF  ! problem reading file, no need to continue
      endif
      read(FN,*,IOSTAT=Reason) ! skip first two lines with comments
      call read_file(Reason, count_lines, read_well)
      if (.not. read_well) then
         print*, 'Could not read line ', count_lines, ' in file '//trim(adjustl(File_name))
         print*, 'SCC cannot be used, proceeding at non-self-consistent level'
         SCC = .false.
         exit RF  ! problem reading file, no need to continue
      endif

      SFE:do while (.not.found_el)
         read(FN,*,IOSTAT=Reason) El_name, U_read
         if (.not. read_well) then
            print*, 'Could not read line ', count_lines, ' in file '//trim(adjustl(File_name))
            print*, 'SCC cannot be used, proceeding at non-self-consistent level'
            SCC = .false.
            exit RF  ! problem reading file, no need to continue
         endif
         ! Check if this is the element we need:
         if ( trim(adjustl(El_name)) == trim(adjustl(matter%Atoms(i)%Name)) ) then
            found_el = .true.
            !matter%Atoms(i)%Hubbard_U = U_read * 0.5d0   ! alternative definition with 1/2
            matter%Atoms(i)%Hubbard_U = U_read  ! [eV]

            rewind(FN)  ! start the search for the next element
            exit SFE ! found element, go to the next one
         endif
      enddo SFE
   enddo RF

3430 continue
   call close_file('close', FN=FN) ! module "Dealing_with_files"
end subroutine read_SCC_Hubbard



subroutine read_k_grid(matter, numpar, Err)
   type(Solid), intent(in) :: matter	! all material parameters
   type(Numerics_param), intent(inout) :: numpar 	! all numerical parameters
   type(Error_handling), intent(inout) :: Err	! error save
   !-------------------------------------------------
   integer :: FN, N, count_lines, Reason, i
   character(200) :: error_message, Error_descript
   character(200) :: Folder_name, Path, File_name
   logical :: file_exist, file_opened, read_well
   
   ! Check if we even need the k grid:
   select case (ABS(numpar%optic_model))	! use multiple k-points, or only gamma
      case (2)	! multiple k points
         Folder_name = trim(adjustl(numpar%input_path))
         Path = trim(adjustl(Folder_name))//trim(adjustl(matter%Name))
         write(File_name, '(a,a,a)') trim(adjustl(Path)), trim(adjustl(numpar%path_sep)), 'k_grid.dat'
         inquire(file=trim(adjustl(File_name)),exist=file_exist)

         if (file_exist) then
            FN = 103
            open(UNIT=FN, FILE = trim(adjustl(File_name)), status = 'old', action='read')
            inquire(file=trim(adjustl(File_name)),opened=file_opened)
            if (.not.file_opened) then
               print*, 'File '//trim(adjustl(File_name))//' could not be opened, using Monkhorst Pack k-points'
               goto 3426
            endif

            ! Count how many grid points are there:
            call Count_lines_in_file(FN, N)	! module "Dealing_with_files"
            
            ! Knwoing the number of k points, allocate the array:
            allocate(numpar%k_grid(N,3))
            numpar%k_grid = 0.0d0
            
            ! Also adjust the nunbers of k-points correspondingly:
            numpar%ixm = ceiling(dble(N)**(1.0d0/3.0d0))
            numpar%iym = numpar%ixm
            numpar%izm = numpar%ixm
            
            ! Read the k points from the file:
            count_lines = 0
            do i = 1, N
               read(FN,*,IOSTAT=Reason) numpar%k_grid(i,1), numpar%k_grid(i,2), numpar%k_grid(i,3)
               call read_file(Reason, count_lines, read_well)
               if (.not. read_well) then
                  print*, 'Could not read line ', count_lines, ' in file '//trim(adjustl(File_name))
                  print*, 'The remaining ', (N-count_lines), ' k points are set as Gamma point (0,0,0)'
                  goto 3426
               endif
            enddo
            
            close(FN)
         else
            print*, 'k-space grid file not found, using Monkhorst Pack k-points'
            goto 3426
         endif
      case default	! gamma point
         ! no need to even care about k space grid
   end select
3426 continue
end subroutine read_k_grid



subroutine read_atomic_parameters(matter, numpar, Err)
   type(Solid), intent(inout) :: matter	! all material parameters
   type(Numerics_param), intent(inout) :: numpar 	! all numerical parameters
   type(Error_handling), intent(inout) :: Err	! error save
   integer i
   character(200) :: Folder_name, File_name, Path
   logical :: file_exist
   
   select case (numpar%At_base)
   case('CDF') ! read data from corresponding *.cdf file
      Folder_name = trim(adjustl(numpar%input_path))
      Path = trim(adjustl(Folder_name))//trim(adjustl(matter%Name))
      write(File_name, '(a,a,a,a)') trim(adjustl(Path)), trim(adjustl(numpar%path_sep)), trim(adjustl(matter%Name)), '.cdf'
      inquire(file=trim(adjustl(File_name)),exist=file_exist)
      if (file_exist) then
         call get_CDF_data(matter, numpar, Err) ! see below
      else
         print*, 'File ', trim(adjustl(File_name)), ' could not be found, use EADL instead of CDF'
         numpar%At_base = 'EADL'
         call get_EADL_data(matter, numpar, Err) ! see below
      endif
   case ('XATOM') ! get data from XATOM code
      ! to be integrated with XATOM later...
   case default ! ('EADL'), read data from EADL database
      call get_EADL_data(matter, numpar, Err) ! see below
   end select
   
!    print*, 'TEST:', allocated(matter%Atoms), size(matter%Atoms), numpar%At_base
!    do i = 1, size(matter%Atoms)
!       !print*, trim(adjustl(matter%Chem)), ' '//trim(adjustl(matter%Atoms(i)%Name)), matter%Atoms(i)%N_CDF(:), matter%Atoms(i)%Shl_dsgnr(:), matter%Atoms(i)%Ip(:), matter%Atoms(i)%Ne_shell(:), matter%Atoms(i)%Auger(:)
!       print*, matter%Atoms(i)%Ne_shell(:)
!    enddo
!    call get_table_of_ij_numbers(matter, numpar) ! table of elements number to locate TB parameterization for different combinations of atoms
end subroutine read_atomic_parameters


! subroutine get_table_of_ij_numbers(matter, numpar) ! table of elements number to locate TB parameterization for different combinations of atoms
!    type(Solid), intent(in) :: matter  ! all material parameters
!    type(Numerics_param), intent(inout) :: numpar ! all numerical parameters
!    integer i, j, coun
!    if (.not.allocated(numpar%El_num_ij)) then
!       allocate(numpar%El_num_ij(matter%N_KAO,matter%N_KAO)) ! element correspondance
!       numpar%El_num_ij = 0
!    endif
!    coun = 0
!    do i = 1, matter%N_KAO
!       do j = i, matter%N_KAO
!          coun = coun + 1
!          numpar%El_num_ij(i,j) = coun ! number of TB parrametrization
!          numpar%El_num_ij(j,i) = numpar%El_num_ij(i,j)
! !          print*, i, j, numpar%El_num_ij(i,j)
!       enddo
!    enddo
! end subroutine get_table_of_ij_numbers



subroutine get_CDF_data(matter, numpar, Err)
   type(Solid), intent(inout) :: matter	! all material parameters
   type(Numerics_param), intent(inout) :: numpar 	! all numerical parameters
   type(Error_handling), intent(inout) :: Err	! error save
   !===============================================
   integer, dimension(:), allocatable :: at_numbers
   real(8), dimension(:), allocatable :: at_percentage
   character(3), dimension(:), allocatable :: at_short_names ! name of the element
   character(25), dimension(:), allocatable :: at_names ! full name of the element
   real(8), dimension(:), allocatable :: at_masses ! mass of each element [Mp]
   integer, dimension(:), allocatable :: at_NVE    ! number of valence electrons
   integer FN1, INFO, i, j, k, Z
   character(100) :: error_message, Error_descript
   character(100) :: Folder_name, Folder_name2, File_name, Path
   logical file_exist, file_opened, read_well
   integer FN, Reason, count_lines, temp
   real(8) retemp

   !Folder_name = 'INPUT_DATA'//trim(adjustl(numpar%path_sep))
   Folder_name = trim(adjustl(numpar%input_path))
   Path = trim(adjustl(Folder_name))//trim(adjustl(matter%Name))
   write(File_name, '(a,a,a,a)') trim(adjustl(Path)), trim(adjustl(numpar%path_sep)), trim(adjustl(matter%Name)), '.cdf'
   inquire(file=trim(adjustl(File_name)),exist=file_exist)

   if (file_exist) then
      !open(NEWUNIT=FN, FILE = trim(adjustl(File_name)), status = 'old')
      FN = 103
      open(UNIT=FN, FILE = trim(adjustl(File_name)), status = 'old', action='read')
      inquire(file=trim(adjustl(File_name)),opened=file_opened)
      if (.not.file_opened) then
!          Error_descript = 'File '//trim(adjustl(File_name))//' could not be opened, the program terminates'
         Error_descript = 'File '//trim(adjustl(File_name))//' could not be opened'
         call Save_error_details(Err, 2, Error_descript)
         print*, trim(adjustl(Error_descript))
         goto 3420
      endif

      count_lines = 0
      read(FN,*,IOSTAT=Reason)	! skip first line with the name of the material
      call read_file(Reason, count_lines, read_well)
      if (.not. read_well) then
         write(Error_descript,'(a,i5,a,$)') 'Could not read line ', count_lines, ' in file '//trim(adjustl(File_name))
         call Save_error_details(Err, 3, Error_descript)
         print*, trim(adjustl(Error_descript))
         goto 3420
      endif

      read(FN,*,IOSTAT=Reason) matter%Chem ! chemical formula of the material
      call read_file(Reason, count_lines, read_well)
      if (.not. read_well) then
         write(Error_descript,'(a,i5,a,$)') 'Could not read line ', count_lines, ' in file '//trim(adjustl(File_name))
         call Save_error_details(Err, 3, Error_descript)
         print*, trim(adjustl(Error_descript))
         goto 3420
      endif

      !Folder_name2 = 'INPUT_DATA'//trim(adjustl(numpar%path_sep))//'Atomic_parameters'
      Folder_name2 = trim(adjustl(numpar%input_path))//trim(adjustl(m_Atomic_parameters))  ! 'Atomic_parameters'
      call Decompose_compound(Folder_name2, matter%Chem, numpar%path_sep, INFO, error_message, matter%N_KAO, at_numbers, &
                  at_percentage, at_short_names, at_names, at_masses, at_NVE) ! molude 'Periodic_table'
      if (INFO .NE. 0) then
         call Save_error_details(Err, INFO, error_message)
         print*, trim(adjustl(error_message))
         goto 3420
      endif
      if (.not.allocated(matter%Atoms)) allocate(matter%Atoms(matter%N_KAO))
      
      do i = 1, matter%N_KAO ! for all sorts of atoms
         matter%Atoms(i)%Z = at_numbers(i)
         matter%Atoms(i)%Name = at_short_names(i)
         matter%Atoms(i)%Ma = at_masses(i)*g_Mp ! [kg]
         matter%Atoms(i)%percentage = at_percentage(i)
         matter%Atoms(i)%NVB = at_NVE(i)
          !print*, matter%Atoms(i)%Name, matter%Atoms(i)%Ma, matter%Atoms(i)%NVB
          !pause 'get_CDF_data'
      enddo

      read(FN,*,IOSTAT=Reason) retemp ! skip this line - density is given elsewhere
      call read_file(Reason, count_lines, read_well)
      if (.not. read_well) then
         write(Error_descript,'(a,i5,a,$)') 'Could not read line ', count_lines, ' in file '//trim(adjustl(File_name))
         call Save_error_details(Err, 3, Error_descript)
         print*, trim(adjustl(Error_descript))
         goto 3420
      endif
      if (matter%dens .LE. 0.0d0) matter%dens = retemp ! in case density is not given elsewhere

      AT_NUM:do i = 1, matter%N_KAO ! for each kind of atoms:
         read(FN,*,IOSTAT=Reason) matter%Atoms(i)%sh	! number of shells in this element
         call read_file(Reason, count_lines, read_well)
         if (.not. read_well) then
            write(Error_descript,'(a,i5,a,$)') 'Could not read line ', count_lines, ' in file '//trim(adjustl(File_name))
            call Save_error_details(Err, 3, Error_descript)
            print*, trim(adjustl(Error_descript))
            goto 3420
         endif

         if (.not. allocated(matter%Atoms(i)%Ne_shell)) allocate(matter%Atoms(i)%Ne_shell(matter%Atoms(i)%sh)) ! allocate number of electrons
         if (.not. allocated(matter%Atoms(i)%Shell_name)) allocate(matter%Atoms(i)%Shell_name(matter%Atoms(i)%sh)) ! allocate shell names
         if (.not. allocated(matter%Atoms(i)%Shl_dsgnr)) allocate(matter%Atoms(i)%Shl_dsgnr(matter%Atoms(i)%sh)) ! allocate shell disignator for each shell
         if (.not. allocated(matter%Atoms(i)%N_CDF)) allocate(matter%Atoms(i)%N_CDF(matter%Atoms(i)%sh)) ! allocate number of electrons
         if (.not. allocated(matter%Atoms(i)%Ip)) allocate(matter%Atoms(i)%Ip(matter%Atoms(i)%sh)) ! allocate ionization potentials
         if (.not. allocated(matter%Atoms(i)%Ek)) allocate(matter%Atoms(i)%Ek(matter%Atoms(i)%sh)) ! allocate mean kinetic energies of the shells
         if (.not. allocated(matter%Atoms(i)%TOCS)) allocate(matter%Atoms(i)%TOCS(matter%Atoms(i)%sh)) ! allocate type of cross-section to be used
         if (.not. allocated(matter%Atoms(i)%El_MFP)) allocate(matter%Atoms(i)%El_MFP(matter%Atoms(i)%sh)) ! allocate electron MFPs
         if (.not. allocated(matter%Atoms(i)%Ph_MFP)) allocate(matter%Atoms(i)%Ph_MFP(matter%Atoms(i)%sh)) ! allocate photon MFPs
         matter%Atoms(i)%Ek = 0.0d0 ! starting value
         !if (.not. allocated(matter%Atoms(i)%Radiat)) then
         !   allocate(matter%Atoms(i)%Radiat(matter%Atoms%sh)) ! allocate Radiative-times
         !   matter%Atoms(i)%Radiat = 1d24 ! to start with
         !endif
         if (.not. allocated(matter%Atoms(i)%Auger)) then
            allocate(matter%Atoms(i)%Auger(matter%Atoms(i)%sh)) ! allocate Auger times
            matter%Atoms(i)%Auger = 1d24 ! to start with
         endif
         if (.not. allocated(matter%Atoms(i)%CDF)) allocate(matter%Atoms(i)%CDF(matter%Atoms(i)%sh)) ! allocate CDF functions

         do j = 1, matter%Atoms(i)%sh	! for all shells:
            ! Number of CDF functions, shell-designator, ionization potential, number of electrons, Auger-time:
            read(FN,*,IOSTAT=Reason) matter%Atoms(i)%N_CDF(j), matter%Atoms(i)%Shl_dsgnr(j), matter%Atoms(i)%Ip(j), matter%Atoms(i)%Ne_shell(j), matter%Atoms(i)%Auger(j)
            call read_file(Reason, count_lines, read_well)
            if (.not. read_well) then
               write(Error_descript,'(a,i5,a,$)') 'Could not read line ', count_lines, ' in file '//trim(adjustl(File_name))
               call Save_error_details(Err, 3, Error_descript)
               print*, trim(adjustl(Error_descript))
               goto 3420
            endif
            matter%Atoms(i)%Shell_name(j) = ''  ! no name yet, to be defined  in the next subroutine

            call check_atomic_data(matter, numpar, Err, i, j, matter%Atoms(i)%sh)   ! below

            DOCDF:if (matter%Atoms(i)%N_CDF(j) .GT. 0) then ! do this shell with provided CDF coefficients
               matter%Atoms(i)%TOCS(j) = 1 ! CDF cross-section
               allocate(matter%Atoms(i)%CDF(j)%A(matter%Atoms(i)%N_CDF(j)))
               allocate(matter%Atoms(i)%CDF(j)%E0(matter%Atoms(i)%N_CDF(j)))
               allocate(matter%Atoms(i)%CDF(j)%G(matter%Atoms(i)%N_CDF(j)))

               do k = 1, matter%Atoms(i)%N_CDF(j)	! for all CDF-functions for this shell
                  read(FN,*,IOSTAT=Reason) matter%Atoms(i)%CDF(j)%E0(k), matter%Atoms(i)%CDF(j)%A(k), matter%Atoms(i)%CDF(j)%G(k)
!                   write(*,*) matter%Atoms(i)%CDF(j)%E0(k), matter%Atoms(i)%CDF(j)%A(k), matter%Atoms(i)%CDF(j)%G(k)
                  if (.not. read_well) then
                     write(Error_descript,'(a,i5,a,$)') 'Could not read line ', count_lines, ' in file '//trim(adjustl(File_name))
                     call Save_error_details(Err, 3, Error_descript)
                     print*, trim(adjustl(Error_descript))
                     goto 3420
                  endif
               enddo

            else DOCDF
               matter%Atoms(i)%TOCS(j) = 0 ! BEB cross-section
            endif DOCDF
         enddo
      enddo AT_NUM
      close(FN)
   else
      write(Error_descript,'(a,$)') 'File '//trim(adjustl(File_name))//' could not be found, the program terminates'
      call Save_error_details(Err, 1, Error_descript)
      print*, trim(adjustl(Error_descript))
      goto 3420
   endif

3420 continue
end subroutine get_CDF_data



subroutine check_atomic_data(matter, numpar, Err, i, cur_shl, shl_tot)
   type(Solid), intent(inout) :: matter	! all material parameters
   type(Numerics_param), intent(inout) :: numpar 	! all numerical parameters
   type(Error_handling), intent(inout) :: Err	! error save
   integer, intent(in) :: i, cur_shl, shl_tot	! No. of atom, current number of shell, total number of shells for this atom
   !===============================================
   character(200) :: Folder_name, File_name, Error_descript
   integer FN, INFO, j, Z, imax, imin, N_shl
   real(8), dimension(:), allocatable :: Nel   ! number of electrons in each shell
   integer, dimension(:), allocatable :: Shl_num ! shell designator
   character(11), dimension(:), allocatable :: Shell_name
   logical :: file_exist, file_opened

   ! Open eadl.all database:
   !Folder_name = 'INPUT_DATA'//trim(adjustl(numpar%path_sep))//'Atomic_parameters'
   Folder_name = trim(adjustl(numpar%input_path))//trim(adjustl(m_Atomic_parameters))   !'Atomic_parameters'
   !File_name = trim(adjustl(Folder_name))//trim(adjustl(numpar%path_sep))//'eadl.all'
   File_name = trim(adjustl(Folder_name))//trim(adjustl(numpar%path_sep))//trim(adjustl(m_EADL_file))
   
   !call open_file('readonly', File_name, FN, INFO, Error_descript)
   INFO = 0
   inquire(file=trim(adjustl(File_name)),exist=file_exist)
   if (.not.file_exist) then
      INFO = 1
      Error_descript = 'File '//trim(adjustl(File_name))//' does not exist, the program terminates'
      call Save_error_details(Err, INFO, Error_descript)
      print*, trim(adjustl(Error_descript))
   else
      !open(NEWUNIT=FN, FILE = trim(adjustl(File_name)), status = 'old')
      FN=104
      open(UNIT=FN, FILE = trim(adjustl(File_name)), status = 'old', action='read')
      inquire(file=trim(adjustl(File_name)),opened=file_opened)
      if (.not.file_opened) then
         INFO = 2
         Error_descript = 'File '//trim(adjustl(File_name))//' could not be opened, the program terminates'
         call Save_error_details(Err, INFO, Error_descript)
         print*, trim(adjustl(Error_descript))
      endif
   endif

   select case (INFO)
   case (0)
      Z =  matter%Atoms(i)%Z ! atomic number

      ! Shell name:
      if (LEN(trim(adjustl(matter%Atoms(i)%Shell_name(cur_shl)))) < 1) then ! take if from EADL-database
         if ( matter%Atoms(i)%Shl_dsgnr(cur_shl) >= 63 ) then
            matter%Atoms(i)%Shell_name(cur_shl) = 'Valence'
         else ! core shell
            call READ_EADL_TYPE_FILE_int(FN, File_name, Z, 912, INFO, error_message=Error_descript, N_shl=N_shl, &
                  Nel=Nel, Shell_name=Shell_name)    ! module "Dealing_with_EADL"
            matter%Atoms(i)%Shell_name(cur_shl) = Shell_name(cur_shl)
         endif
      endif
      ! Number of electrons in this shell:
      if (matter%Atoms(i)%Ne_shell(cur_shl) .LT. 0) then ! take if from EADL-database
         call READ_EADL_TYPE_FILE_int(FN, File_name, Z, 912, INFO, error_message=Error_descript, N_shl=N_shl, &
                  Nel=Nel, Shl_num=Shl_num) ! module "Dealing_with_EADL"
         if (INFO .NE. 0) then
            call Save_error_details(Err, INFO, Error_descript)
            print*, trim(adjustl(Error_descript))
            goto 9999
         endif
         imax = 0
         imin = 0
         call select_imin_imax(imin, imax, matter%Atoms(i)%Shl_dsgnr(cur_shl)) ! sum subshells, module "Dealing_with_EADL"
         if (imax .GT. 0) then
            matter%Atoms(i)%Ne_shell(cur_shl) = SUM(Nel, MASK=((Shl_num .GE. imin) .AND. (Shl_num .LE. imax)))
         else
            matter%Atoms(i)%Ne_shell(cur_shl) = Nel(cur_shl)
         endif 
      endif
      ! Ionization potential:
      if (matter%Atoms(i)%Ip(cur_shl) .LT. 0.0d0) then ! take if from EADL-database
         ! Read auger-times:
         call READ_EADL_TYPE_FILE_real(FN, File_name, Z, 913, matter%Atoms(i)%Ip, cur_shl=cur_shl, shl_tot=shl_tot, &
               Shl_dsgtr=matter%Atoms(i)%Shl_dsgnr(cur_shl), INFO=INFO, error_message=Error_descript) ! module "Dealing_with_EADL"
         if (INFO .NE. 0) then
            call Save_error_details(Err, INFO, Error_descript)
            print*, trim(adjustl(Error_descript))
            goto 9999
         endif
         ! Read kinetic energies:
         call READ_EADL_TYPE_FILE_real(FN, File_name, Z, 914, matter%Atoms(i)%Ek, cur_shl=cur_shl, shl_tot=shl_tot, &
               Shl_dsgtr=matter%Atoms(i)%Shl_dsgnr(cur_shl), INFO=INFO, error_message=Error_descript) ! module "Dealing_with_EADL"
         if (INFO .NE. 0) then
            call Save_error_details(Err, INFO, Error_descript)
            print*, trim(adjustl(Error_descript))
            goto 9999
         endif
         !matter%Atoms(i)%TOCS(cur_shl) = 0 ! BEB cross-section
      endif
      ! Auger-decay time:
      if (matter%Atoms(i)%Auger(cur_shl).LT. 0.0d0) then ! take if from EADL-database
        ! Read auger-times:
        call READ_EADL_TYPE_FILE_real(FN, File_name, Z, 922, matter%Atoms(i)%Auger, cur_shl=cur_shl, shl_tot=shl_tot, &
               Shl_dsgtr=matter%Atoms(i)%Shl_dsgnr(cur_shl), INFO=INFO, error_message=Error_descript) ! module "Dealing_with_EADL"
        if (INFO .NE. 0) then
            call Save_error_details(Err, INFO, Error_descript)
            print*, trim(adjustl(Error_descript))
            goto 9999
         endif
      endif
      close (FN)
   case default
      call Save_error_details(Err, INFO, Error_descript)
      print*, trim(adjustl(Error_descript))
   end select
9999 continue
end subroutine check_atomic_data



subroutine get_EADL_data(matter, numpar, Err)
   type(Solid), intent(inout) :: matter	! all material parameters
   type(Numerics_param), intent(inout) :: numpar 	! all numerical parameters
   type(Error_handling), intent(inout) :: Err	! error save
   !===============================================
   integer, dimension(:), allocatable :: at_numbers
   real(8), dimension(:), allocatable :: at_percentage
   character(3), dimension(:), allocatable :: at_short_names ! name of the element
   character(25), dimension(:), allocatable :: at_names ! full name of the element
   real(8), dimension(:), allocatable :: at_masses ! mass of each element [Mp]
   integer, dimension(:), allocatable :: at_NVE    ! number of valence electrons
   integer FN1, INFO, i, j, Z, old_shl_num, mod_shl_num, shl_dsg
   real(8) E_gap
   character(100) :: error_message, Error_descript
   character(100) :: Folder_name, File_name
   logical file_exist, file_opened

   !Folder_name = 'INPUT_DATA'//trim(adjustl(numpar%path_sep))//'Atomic_parameters'
   Folder_name = trim(adjustl(numpar%input_path))//trim(adjustl(m_Atomic_parameters))   !'Atomic_parameters'

   call Decompose_compound(Folder_name, matter%Chem, numpar%path_sep, INFO, error_message, matter%N_KAO, at_numbers, at_percentage, at_short_names, at_names, at_masses, at_NVE) ! molude 'Periodic_table'
   if (INFO .NE. 0) then
      call Save_error_details(Err, INFO, error_message)
      print*, trim(adjustl(error_message))
      goto 3419
   endif
   if (.not.allocated(matter%Atoms)) allocate(matter%Atoms(matter%N_KAO))
   do i = 1, matter%N_KAO ! for all sorts of atoms
      matter%Atoms(i)%Z = at_numbers(i)
      matter%Atoms(i)%Name = at_short_names(i)
      !matter%Atoms(i)%Ma = at_masses(i)*g_Mp ! [kg]
      matter%Atoms(i)%Ma = at_masses(i)*g_amu ! [kg]
      matter%Atoms(i)%percentage = at_percentage(i)
      matter%Atoms(i)%NVB = at_NVE(i)
   enddo

   ! Open eadl.all database:
   !File_name = trim(adjustl(Folder_name))//trim(adjustl(numpar%path_sep))//'eadl.all'
   File_name = trim(adjustl(Folder_name))//trim(adjustl(numpar%path_sep))//trim(adjustl(m_EADL_file))
   inquire(file=trim(adjustl(File_name)),exist=file_exist)
   if (.not.file_exist) then
      Error_descript = 'File '//trim(adjustl(File_name))//' does not exist, the program terminates'
      call Save_error_details(Err, 1, Error_descript)
      print*, trim(adjustl(Error_descript))
      goto 3419
   endif

!    print*, 'File ', trim(adjustl(File_name)), ' is read'

   !open(NEWUNIT=FN1, FILE = trim(adjustl(File_name)), status = 'old')
   FN1=105
   open(UNIT=FN1, FILE = trim(adjustl(File_name)), status = 'old', action='read')
   inquire(file=trim(adjustl(File_name)),opened=file_opened)
   if (file_opened) then
     do i = 1, matter%N_KAO ! for all atomic kinds of the compound
      Z =  matter%Atoms(i)%Z ! atomic number

      ! First, get the total number of shells of this atom:
      call READ_EADL_TYPE_FILE_int(FN1, File_name, Z, 912, INFO, error_message, matter%Atoms(i)%sh, matter%Atoms(i)%Ne_shell, Shl_num=matter%Atoms(i)%Shl_dsgnr_atomic, Ip=matter%Atoms(i)%Ip)    ! module "Dealing_with_EADL"
      if (INFO .NE. 0) then
         call Save_error_details(Err, INFO, Error_descript)
         print*, trim(adjustl(Error_descript))
         goto 3419
      endif

!       print*, 'READ_EADL_TYPE_FILE_int is done', i

      ! Get values for all parameters:
      call READ_EADL_TYPE_FILE_real(FN1, File_name, Z, 913, matter%Atoms(i)%Ip, INFO=INFO, error_message=Error_descript) ! read binding energies, module "Dealing_with_EADL"
      ! Make sure we start reading it again from the start:
      rewind(FN1)

!       print*, 'READ_EADL_TYPE_FILE_real is done', i


      ! Then correct it to exclude VB:
      call exclude_BV(i, matter%Atoms(i)%sh, matter%Atoms(i)%Ne_shell, matter%Atoms(i)%NVB, mod_shl_num)
      old_shl_num = matter%Atoms(i)%sh ! save old uppermost level to use as initial band gap
      matter%Atoms(i)%sh = mod_shl_num ! new number of shells
!       print*, 'itest', i, matter%Atoms(i)%sh , mod_shl_num 
      E_gap = matter%Atoms(i)%Ip(old_shl_num) ! [eV] save uppermost level
      deallocate(matter%Atoms(i)%Ip) ! to use it next time for new number of shells

      ! Now get the parameters for all the shells (except VB):
      call READ_EADL_TYPE_FILE_int(FN1, File_name, Z, 912, INFO, error_message, matter%Atoms(i)%sh, matter%Atoms(i)%Ne_shell, Shell_name=matter%Atoms(i)%Shell_name, Shl_num=matter%Atoms(i)%Shl_dsgnr, Ip=matter%Atoms(i)%Ip, Ek=matter%Atoms(i)%Ek, Auger=matter%Atoms(i)%Auger, REDO=.false.)    ! module "Dealing_with_EADL"
      if (INFO .NE. 0) then
         call Save_error_details(Err, INFO, Error_descript)
         print*, trim(adjustl(Error_descript))
         goto 3419
      endif

!       print*, i, matter%Atoms(i)%Shl_dsgnr_atomic, matter%Atoms(i)%Shl_dsgnr
!       pause 'Shl_dsgnr_atomic'

!       print*, 'READ_EADL_TYPE_FILE_real is done: Auger', i

      ! Get values for all parameters:
      call READ_EADL_TYPE_FILE_real(FN1, File_name, Z, 913, matter%Atoms(i)%Ip, INFO=INFO, error_message=Error_descript) ! read binding energies, module "Dealing_with_EADL"
      if (INFO .NE. 0) then
         call Save_error_details(Err, INFO, Error_descript)
         print*, trim(adjustl(Error_descript))
         goto 3419
      endif

      call READ_EADL_TYPE_FILE_real(FN1, File_name, Z, 914, matter%Atoms(i)%Ek, INFO=INFO, error_message=Error_descript) ! read kinetic energies, module "Dealing_with_EADL"
      if (INFO .NE. 0) then
         call Save_error_details(Err, INFO, Error_descript)
         print*, trim(adjustl(Error_descript))
         goto 3419
      endif

      if (.not. allocated(matter%Atoms(i)%TOCS)) then
         allocate(matter%Atoms(i)%TOCS(matter%Atoms(i)%sh)) ! allocate type of cross-section to be used
         matter%Atoms(i)%TOCS = 0 ! do all BEB cross-sections
      endif

      if (.not. allocated(matter%Atoms(i)%El_MFP)) allocate(matter%Atoms(i)%El_MFP(matter%Atoms(i)%sh)) ! allocate electron MFPs
      if (.not. allocated(matter%Atoms(i)%Ph_MFP)) allocate(matter%Atoms(i)%Ph_MFP(matter%Atoms(i)%sh)) ! allocate photon MFPs
      !call READ_EADL_TYPE_FILE_real(FN1, File_name, Z, 921, Target_atoms(i)%Radiat, INFO=INFO, error_message=Error_descript) ! radiative decay, module "Dealing_with_EADL"

      call READ_EADL_TYPE_FILE_real(FN1, File_name, Z, 922, matter%Atoms(i)%Auger, INFO=INFO, error_message=Error_descript) ! read auger-times, module "Dealing_with_EADL"
      if (INFO .NE. 0) then
         call Save_error_details(Err, INFO, Error_descript)
         print*, trim(adjustl(Error_descript))
         goto 3419
      endif

      do j = 1,size(matter%Atoms(i)%Ip)
         if (matter%Atoms(i)%Auger(j) <= 0.0d0) then ! no auger possible/nothing in the database
            matter%Atoms(i)%Auger(j) = 1d30
         else ! there is some value in the database, convert it into our units:
            matter%Atoms(i)%Auger(j)=1d15*g_h/(g_e*matter%Atoms(i)%Auger(j)) ! [fs]
         endif
         ! Check that all deep shell holes decay:
         if (j > 1) then ! all shells except K-shell for now:
            if (matter%Atoms(i)%Auger(j) >= 1d20) matter%Atoms(i)%Auger(j) = matter%Atoms(i)%Auger(j-1)
         endif
!          print*, i, j, matter%Atoms(i)%Auger(j)
      enddo ! j

      ! Now, modify the VB values where possible:
      if (i == 1) then
         matter%Atoms(i)%Shell_name(mod_shl_num) = 'Valence'
         matter%Atoms(i)%Shl_dsgnr(mod_shl_num) = 63
         matter%Atoms(i)%Ip(mod_shl_num) = E_gap ! VB only for 1st kind of atoms
         matter%Atoms(i)%Ek(mod_shl_num) = 0.0d0 ![eV]
         matter%Atoms(i)%Auger(mod_shl_num) = 1d23 ! [fs] no Auger-decays of VB
         matter%Atoms(i)%Ne_shell(mod_shl_num) = matter%Atoms(i)%NVB ! number of valence electrons
      endif
!       print*, 'Total numbert of shells:', matter%Atoms(i)%sh
!       do j = 1, matter%Atoms(i)%sh
!          print*, 'Names:', trim(adjustl(matter%Atoms(i)%Shell_name(j)))
!       enddo
!       print*, 'Shl_dsgnr:', matter%Atoms(i)%Shl_dsgnr
!       print*, 'Ne_shell:', matter%Atoms(i)%Ne_shell
!       print*, 'Ip:', matter%Atoms(i)%Ip
!       print*, 'Ek:', matter%Atoms(i)%Ek
!       print*, 'Auger:', matter%Atoms(i)%Auger
!       pause "get_EADL_data"

        rewind(FN1) ! for the next element, start over from the beginning of the file
     enddo ! i
     close(FN1)
   else 
     Error_descript = 'File '//trim(adjustl(File_name))//' could not be opened, the program terminates'
     call Save_error_details(Err, 2, Error_descript)
     print*, trim(adjustl(Error_descript))
     goto 3419
   endif

3419 continue
end subroutine get_EADL_data


subroutine exclude_BV(NOA, sh, Ne_shell, NVB, mod_shl_num, N_shl)
   integer, intent(in) :: NOA   ! number of atom in the compound
   integer, intent(inout) :: sh ! number of shells of the element
   real(8), dimension(:), allocatable, intent(inout) :: Ne_shell ! number of electron in each shell
   integer, intent(in) :: NVB   ! number valence electrons according to periodic table
   integer, intent(out) :: mod_shl_num    ! modified number of shells
   integer, intent(in), optional :: N_shl ! if we already counted the number of shells 
   integer i, counter
   real(8) Ne_cur
   real(8), dimension(size(Ne_shell)) :: Ne_temp
   if (.not.present(N_shl)) then
      Ne_cur = 0.0d0 ! to start counting
      counter = 0
      SH_COUNT: do i = sh,1,-1
         Ne_cur = Ne_cur + Ne_shell(i)
         counter = counter + 1
         if (Ne_cur >= NVB) exit SH_COUNT
      enddo SH_COUNT
      if (NOA == 1) then 
         mod_shl_num = sh - counter + 1 ! all deep shells plus one for VB
      else
         mod_shl_num = sh - counter     ! all deep shells, but no VB for other sorts of atoms
      endif
   else
      mod_shl_num = N_shl ! all deep shells plus one for VB
   endif
!    if (mod_shl_num < 1) mod_shl_num = 1 ! for elements with just 1 shell filled (H and He)

!    print*, NVB, mod_shl_num, sh
!    print*, Ne_shell(:)
!    pause 'exclude_BV - 0'

   if (size(Ne_shell) /= mod_shl_num) then ! redefine it:
      Ne_temp = Ne_shell
      if (allocated(Ne_shell)) deallocate(Ne_shell)
      allocate(Ne_shell(mod_shl_num)) ! new size
      RESHAP: do i = 1, mod_shl_num-1 ! deep shells are correct
         Ne_shell(i) = Ne_temp(i)
      enddo RESHAP
      if (mod_shl_num > 0) Ne_shell(mod_shl_num) = NVB ! this is number of electrons in the VB
   endif


!     print*, NVB, mod_shl_num, sh
!     print*, Ne_shell(:)
!     pause 'exclude_BV'
end subroutine exclude_BV 



subroutine read_TB_parameters(matter, numpar, TB_Repuls, TB_Hamil, TB_Waals, TB_Coul, TB_Expwall, Err)
   type(Solid), intent(in) :: matter	! all material parameters
   type(Numerics_param), intent(inout) :: numpar 	! all numerical parameters
   ! For polymorphic variables:
   class(TB_repulsive), dimension(:,:), allocatable, intent(out) :: TB_Repuls   ! parameters of the repulsive part of TB
   class(TB_Hamiltonian), dimension(:,:), allocatable, intent(out) ::  TB_Hamil ! parameters of the Hamiltonian of TB
   class(TB_vdW),  dimension(:,:), allocatable, intent(out) :: TB_Waals         ! parameters of the van der Waals for TB
   class(TB_Coulomb),  dimension(:,:), allocatable, intent(out) :: TB_Coul	! parameters of the Coulomb together with TB
   class(TB_Exp_wall),  dimension(:,:), allocatable, intent(out) :: TB_Expwall	! parameters of the exponential wall with TB
   type(Error_handling), intent(inout) :: Err	! error save
   !========================================================
   integer FN, count_lines, Reason, INFO, i, j !, N
   character(500) :: Error_descript, Folder_name, File_name, Path, ch_temp
   logical file_exists, file_opened, read_well
   !Folder_name = 'INPUT_DATA'//trim(adjustl(numpar%path_sep))
   Folder_name = trim(adjustl(numpar%input_path))
   Path = trim(adjustl(Folder_name))//trim(adjustl(matter%Name))
   
   do_first:do i = 1, matter%N_KAO
      do_second:do j = 1, matter%N_KAO
         ! First read Hamiltonian (hopping integrals) parametrization:
         write(ch_temp,'(a)') trim(adjustl(matter%Atoms(i)%Name))//'_'//trim(adjustl(matter%Atoms(j)%Name))//'_'
         write(File_name, '(a,a,a)') trim(adjustl(Path)), trim(adjustl(numpar%path_sep)), trim(adjustl(ch_temp))//'TB_Hamiltonian_parameters.txt'
         inquire(file=trim(adjustl(File_name)),exist=file_exists)
         !print*, trim(adjustl(File_name)), file_exists
!          if (.not.file_exists) then ! try inverse combination of atoms in the file-name:
!             write(ch_temp,'(a)') trim(adjustl(matter%Atoms(j)%Name))//'_'//trim(adjustl(matter%Atoms(i)%Name))//'_'
!             write(File_name, '(a,a,a)') trim(adjustl(Path)), trim(adjustl(numpar%path_sep)), trim(adjustl(ch_temp))//'TB_Hamiltonian_parameters.txt'
!             inquire(file=trim(adjustl(File_name)),exist=file_exists)
!          endif
         if (.not.file_exists) then ! try general name used for multiple species at once:
            write(*,'(a,$)') 'File '//trim(adjustl(File_name))//' could not be found. '
            write(File_name, '(a,a,a)') trim(adjustl(Path)), trim(adjustl(numpar%path_sep)), 'TB_Hamiltonian_parameters.txt'
            write(*,'(a)') 'Trying '//trim(adjustl(File_name))//' file instead.'
            inquire(file=trim(adjustl(File_name)),exist=file_exists)
         endif
         
         if (file_exists) then
            !open(NEWUNIT=FN, FILE = trim(adjustl(File_name)), status = 'old', action='READ')
            FN=106
            open(UNIT=FN, FILE = trim(adjustl(File_name)), status = 'old', action='READ')
            inquire(file=trim(adjustl(File_name)),opened=file_opened)
            if (.not.file_opened) then
               Error_descript = 'File '//trim(adjustl(File_name))//' could not be opened, the program terminates'
               call Save_error_details(Err, 2, Error_descript)
               print*, trim(adjustl(Error_descript))
               goto 3421
            endif
            count_lines = 0
            INFO = 0

            ! Read first line to figure out which TB parametrization is used for this material:
            read(FN,*,IOSTAT=Reason) ch_temp
            call read_file(Reason, count_lines, read_well)
            if (.not. read_well) then
               write(Error_descript,'(a,i5,a,$)') 'Could not read line ', count_lines, ' in file '//trim(adjustl(File_name))
               call Save_error_details(Err, 3, Error_descript)
               print*, trim(adjustl(Error_descript))
               goto 3421
            endif
            if (j .GT. 1) then
               if (trim(adjustl(ch_temp)) .NE. trim(adjustl(TB_Hamil(1,1)%Param)) ) then
                  write(Error_descript,'(a)') 'Format of TB-Hamiltonian parameters "'//trim(adjustl(ch_temp))//'" does not coinside with parameters in the first file "'//trim(adjustl(TB_Hamil(1,1)%Param))//'". Inconsistent parameterization is not allowed.'
                  call Save_error_details(Err, 5, Error_descript)
                  print*, trim(adjustl(Error_descript))
                  goto 3421
               endif
            endif

            ! Make the TB parameters of a selected class, depending on what is read in the file:
            select case (trim(adjustl(ch_temp)))
            case ('Pettifor')
               if (.not.allocated(TB_Hamil)) then
                  allocate(TB_H_Pettifor::TB_Hamil(matter%N_KAO,matter%N_KAO)) ! make it for Pettifor parametrization
                  TB_Hamil%Param = ''
               endif
               TB_Hamil(i,j)%Param = trim(adjustl(ch_temp))
            case ('Molteni')
               if (.not.allocated(TB_Hamil)) then
                  allocate(TB_H_Molteni::TB_Hamil(matter%N_KAO,matter%N_KAO)) ! make it for Molteni parametrization
                  TB_Hamil%Param = ''
               endif
               TB_Hamil(i,j)%Param = trim(adjustl(ch_temp))
            case ('Fu')
               if (.not.allocated(TB_Hamil)) then
                  allocate(TB_H_Fu::TB_Hamil(matter%N_KAO,matter%N_KAO)) ! make it for Fu parametrization
                  TB_Hamil%Param = ''
               endif
               TB_Hamil(i,j)%Param = trim(adjustl(ch_temp))
            case ('Mehl', 'NRL')
               if (.not.allocated(TB_Hamil)) then
                  allocate(TB_H_NRL::TB_Hamil(matter%N_KAO,matter%N_KAO)) ! make it for Mehl parametrization
                  TB_Hamil%Param = ''
               endif
               TB_Hamil(i,j)%Param = trim(adjustl(ch_temp))

            case ('DFTB')
               if (.not.allocated(TB_Hamil)) then
                  allocate(TB_H_DFTB::TB_Hamil(matter%N_KAO,matter%N_KAO)) ! make it for DFTB parametrization
                  TB_Hamil%Param = ''
               endif
               TB_Hamil(i,j)%Param = trim(adjustl(ch_temp))
               ! DFTB skf files contain parameters for both Hamiltonian and Repulsive potential, allocate both of them here:
               if (.not.allocated(TB_Repuls)) then
                  allocate(TB_Rep_DFTB::TB_Repuls(matter%N_KAO,matter%N_KAO)) ! make it for DFTB parametrization
                  TB_Repuls%Param = ''
               endif
               TB_Repuls(i,j)%Param = trim(adjustl(ch_temp))

            case ('DFTB_no_repulsion', 'DFTB_no_repulsive', 'DFTB_no_rep')
               if (.not.allocated(TB_Hamil)) then
                  allocate(TB_H_DFTB::TB_Hamil(matter%N_KAO,matter%N_KAO)) ! make it for DFTB parametrization
                  TB_Hamil%Param = ''
               endif
               TB_Hamil(i,j)%Param = trim(adjustl(ch_temp))
               ! DFTB skf files does not contain Repulsive potential, allocate special case:
               if (.not.allocated(TB_Repuls)) then
                  allocate(TB_Rep_DFTB_no::TB_Repuls(matter%N_KAO,matter%N_KAO)) ! make it for DFTB parametrization
                  TB_Repuls%Param = ''
               endif
               TB_Repuls(i,j)%Param = trim(adjustl(ch_temp))

            case ('3TB')
               if (.not.allocated(TB_Hamil)) then
                  allocate(TB_H_3TB::TB_Hamil(matter%N_KAO,matter%N_KAO)) ! make it for 3TB parametrization
                  TB_Hamil%Param = ''
               endif
               TB_Hamil(i,j)%Param = trim(adjustl(ch_temp))

               if (matter%N_KAO > 2) then
                  write(Error_descript,'(a,a,$)') '3TB-parametrization does not support more then binary compounds '
                  call Save_error_details(Err, 4, Error_descript)
                  print*, trim(adjustl(Error_descript))
                  goto 3421
               endif

            case ('BOP')
               if (.not.allocated(TB_Hamil)) then
                  allocate(TB_H_BOP::TB_Hamil(matter%N_KAO,matter%N_KAO)) ! make it for BOP parametrization
                  TB_Hamil%Param = ''
               endif
               TB_Hamil(i,j)%Param = trim(adjustl(ch_temp))
               ! BOP files contain parameters for both Hamiltonian and Repulsive potential, allocate both of them here:
               if (.not.allocated(TB_Repuls)) then
                  allocate(TB_Rep_BOP::TB_Repuls(matter%N_KAO,matter%N_KAO)) ! make it for BOP parametrization
                  TB_Repuls%Param = ''
               endif
               TB_Repuls(i,j)%Param = trim(adjustl(ch_temp))

            case ('xTB', 'GFN', 'GFN0')
               if (.not.allocated(TB_Hamil)) then
                  allocate(TB_H_xTB::TB_Hamil(matter%N_KAO,matter%N_KAO)) ! make it for xTB parametrization
                  TB_Hamil%Param = ''
               endif
               TB_Hamil(i,j)%Param = trim(adjustl(ch_temp))
               if (.not.allocated(TB_Repuls)) then
                  allocate(TB_Rep_xTB::TB_Repuls(matter%N_KAO,matter%N_KAO)) ! make it for xTB parametrization
                  TB_Repuls%Param = ''
               endif
               TB_Repuls(i,j)%Param = trim(adjustl(ch_temp))

            case default
               write(Error_descript,'(a,a,$)') 'Wrong TB-Hamiltonian parametrization class '//trim(adjustl(ch_temp))//' specified in file '//trim(adjustl(File_name))
               call Save_error_details(Err, 4, Error_descript)
               print*, trim(adjustl(Error_descript))
               goto 3421
            end select

            ! Prior to use TB parameters, we now always have to find out which class they belong to:
            select type (TB_Hamil)
            type is (TB_H_Pettifor)
               Error_descript = ''
               !call read_Pettifor_TB_Hamiltonian(FN, numpar%El_num_ij(i,j), TB_Hamil, Error_descript, INFO)
               call read_Pettifor_TB_Hamiltonian(FN, i,j, TB_Hamil, Error_descript, INFO)
               if (INFO .NE. 0) then
                  Err%Err_descript = trim(adjustl(Error_descript))//' in file '//trim(adjustl(File_name)) 
                  call Save_error_details(Err, INFO, Err%Err_descript)
                  print*, trim(adjustl(Err%Err_descript))
                  goto 3421
               endif
!                print*, trim(adjustl(matter%Atoms(i)%Name))//'_'//trim(adjustl(matter%Atoms(j)%Name))//' TB_Hamil ', TB_Hamil(i,j)
            type is (TB_H_Molteni)
               Error_descript = ''
               call read_Molteni_TB_Hamiltonian(FN, i,j, TB_Hamil, Error_descript, INFO)
               if (INFO .NE. 0) then
                  Err%Err_descript = trim(adjustl(Error_descript))//' in file '//trim(adjustl(File_name)) 
                  call Save_error_details(Err, INFO, Err%Err_descript)
                  print*, trim(adjustl(Err%Err_descript))
                  goto 3421
               endif
!                print*, trim(adjustl(matter%Atoms(i)%Name))//'_'//trim(adjustl(matter%Atoms(j)%Name))//' TB_Hamil ', TB_Hamil(i,j)
             type is (TB_H_Fu)
               Error_descript = ''
               !call read_Pettifor_TB_Hamiltonian(FN, numpar%El_num_ij(i,j), TB_Hamil, Error_descript, INFO)
               call read_Fu_TB_Hamiltonian(FN, i,j, TB_Hamil, Error_descript, INFO)
               if (INFO .NE. 0) then
                  Err%Err_descript = trim(adjustl(Error_descript))//' in file '//trim(adjustl(File_name)) 
                  call Save_error_details(Err, INFO, Err%Err_descript)
                  print*, trim(adjustl(Err%Err_descript))
                  goto 3421
               endif
            type is (TB_H_NRL)
               Error_descript = ''
               call read_Mehl_TB_Hamiltonian(FN, i,j, TB_Hamil, Error_descript, INFO)   ! below
               if (INFO .NE. 0) then
                  Err%Err_descript = trim(adjustl(Error_descript))//' in file '//trim(adjustl(File_name)) 
                  call Save_error_details(Err, INFO, Err%Err_descript)
                  print*, trim(adjustl(Err%Err_descript))
                  goto 3421
               endif
            type is (TB_H_DFTB) !in this case, read both Hamiltonian and Repulsive parts together:
               Error_descript = ''
               select type (TB_Repuls)  ! to confirm that repulsive part is consistent with the Hamiltonian
               type is (TB_Rep_DFTB)   ! repulsive parameters provided in the skf-file
                  call read_DFTB_TB_Params(FN, i,j, TB_Hamil, TB_Repuls, numpar, matter, Error_descript, INFO) ! below
               type is (TB_Rep_DFTB_no)   ! no repulsive parameters in skf-file
                  call read_DFTB_TB_Params_no_rep(FN, i,j, TB_Hamil, TB_Repuls, numpar, matter, Error_descript, INFO) ! below
               endselect
               if (INFO .NE. 0) then
                  Err%Err_descript = trim(adjustl(Error_descript))//' in file '//trim(adjustl(File_name)) 
                  call Save_error_details(Err, INFO, Err%Err_descript)
                  print*, trim(adjustl(Err%Err_descript))
                  goto 3421
               endif
            type is (TB_H_3TB)
               Error_descript = ''
               call read_3TB_TB_Params(FN, i, j, TB_Hamil, numpar, matter, Error_descript, INFO) ! below
               if (INFO .NE. 0) then
                  Err%Err_descript = trim(adjustl(Error_descript))//' in file '//trim(adjustl(File_name))
                  call Save_error_details(Err, INFO, Err%Err_descript)
                  print*, trim(adjustl(Err%Err_descript))
                  goto 3421
               endif
            type is (TB_H_BOP) !in this case, read both Hamiltonian and Repulsive parts together:
               Error_descript = ''
               select type (TB_Repuls)  ! to confirm that repulsive part is consistent with the Hamiltonian
               type is (TB_Rep_BOP)
                  call read_BOP_TB_Params(FN, i,j, TB_Hamil, TB_Repuls, numpar, matter, Error_descript, INFO) ! below
               endselect
               if (INFO .NE. 0) then
                  Err%Err_descript = trim(adjustl(Error_descript))//' in file '//trim(adjustl(File_name)) 
                  call Save_error_details(Err, INFO, Err%Err_descript)
                  print*, trim(adjustl(Err%Err_descript))
                  goto 3421
               endif
             type is (TB_H_xTB) !in this case, read both Hamiltonian and Repulsive parts together:
               Error_descript = ''
               select type (TB_Repuls)  ! to confirm that repulsive part is consistent with the Hamiltonian
               type is (TB_Rep_xTB)
                  call read_xTB_Params(FN, i,j, TB_Hamil, TB_Repuls, numpar, matter, Error_descript, INFO) ! below
               endselect
               if (INFO .NE. 0) then
                  Err%Err_descript = trim(adjustl(Error_descript))//' called from file '//trim(adjustl(File_name))
                  call Save_error_details(Err, INFO, Err%Err_descript)
                  print*, trim(adjustl(Err%Err_descript))
                  goto 3421
               endif
            end select
            close(FN)
         else
            write(Error_descript,'(a,$)') 'File '//trim(adjustl(File_name))//' could not be found, the program terminates'
            call Save_error_details(Err, 1, Error_descript)
            print*, trim(adjustl(Error_descript))
            goto 3421
         endif


         !rrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrr
         ! Now read repulsive part parametrization:
         write(ch_temp,'(a)') trim(adjustl(matter%Atoms(i)%Name))//'_'//trim(adjustl(matter%Atoms(j)%Name))//'_'
         write(File_name, '(a,a,a)') trim(adjustl(Path)), trim(adjustl(numpar%path_sep)), trim(adjustl(ch_temp))//'TB_Repulsive_parameters.txt'
         inquire(file=trim(adjustl(File_name)),exist=file_exists)
!          print*, trim(adjustl(File_name)), file_exists
!          if (.not.file_exists) then ! try inverse combination of atoms in the file-name:
!             write(ch_temp,'(a)') trim(adjustl(matter%Atoms(j)%Name))//'_'//trim(adjustl(matter%Atoms(i)%Name))//'_'
!             write(File_name, '(a,a,a)') trim(adjustl(Path)), trim(adjustl(numpar%path_sep)), trim(adjustl(ch_temp))//'TB_Repulsive_parameters.txt'
!             inquire(file=trim(adjustl(File_name)),exist=file_exists)
!             !print*, trim(adjustl(File_name)), file_exists
!          endif
         if (.not.file_exists) then ! try general name used for multiple species at once:
            write(*,'(a,$)') 'File '//trim(adjustl(File_name))//' could not be found. '
            write(File_name, '(a,a,a)') trim(adjustl(Path)), trim(adjustl(numpar%path_sep)), 'TB_Repulsive_parameters.txt'
            write(*,'(a)') 'Trying '//trim(adjustl(File_name))//' file instead.'
            inquire(file=trim(adjustl(File_name)),exist=file_exists)
         endif

         if (file_exists) then
            !open(NEWUNIT=FN, FILE = trim(adjustl(File_name)), status = 'old', action='READ')
            FN=107
            open(UNIT=FN, FILE = trim(adjustl(File_name)), status = 'old', action='READ')
            inquire(file=trim(adjustl(File_name)),opened=file_opened)
            if (.not.file_opened) then
               Error_descript = 'File '//trim(adjustl(File_name))//' could not be opened, the program terminates'
               call Save_error_details(Err, 2, Error_descript)
               print*, trim(adjustl(Error_descript))
               goto 3421
            endif
            count_lines = 0
            INFO = 0

            ! Read first line to figure out which TB parametrization is used for this material:
            read(FN,*,IOSTAT=Reason) ch_temp
            call read_file(Reason, count_lines, read_well)
            if (.not. read_well) then
               write(Error_descript,'(a,i5,a,$)') 'Could not read line ', count_lines, ' in file '//trim(adjustl(File_name))
               call Save_error_details(Err, 3, Error_descript)
               print*, trim(adjustl(Error_descript))
               goto 3421
            endif

            if (j .GT. 1) then
               if (trim(adjustl(ch_temp)) .NE. trim(adjustl(TB_Repuls(1,1)%Param)) ) then
                  write(Error_descript,'(a,$)') 'Format of TB-repulseive parameters "', trim(adjustl(ch_temp)), '" does not coinside with parameters in the first file "'//trim(adjustl(TB_Repuls(1,1)%Param))//'" .Inconsistent parameterization is not allowed.'
                  call Save_error_details(Err, 5, Error_descript)
                  print*, trim(adjustl(Error_descript))
                  goto 3421
               endif
            endif

            ! Make the TB parameters of a selected class, depending on what is read in the file:
            select case (trim(adjustl(ch_temp)))
            case ('Pettifor')
               if (.not.allocated(TB_Repuls)) then
                  allocate(TB_Rep_Pettifor::TB_Repuls(matter%N_KAO,matter%N_KAO)) ! make it for Pettifor parametrization
                  TB_Repuls%Param = ''
               endif
               TB_Repuls(i,j)%Param = trim(adjustl(ch_temp))
            case ('Molteni')
               if (.not.allocated(TB_Repuls)) then
                  allocate(TB_Rep_Molteni::TB_Repuls(matter%N_KAO,matter%N_KAO)) ! make it for Molteni parametrization
                  TB_Repuls%Param = ''
               endif
               TB_Repuls(i,j)%Param = trim(adjustl(ch_temp))
             case ('Fu')
               if (.not.allocated(TB_Repuls)) then
                  allocate(TB_Rep_Fu::TB_Repuls(matter%N_KAO,matter%N_KAO)) ! make it for Fu parametrization
                  TB_Repuls%Param = ''
               endif
               TB_Repuls(i,j)%Param = trim(adjustl(ch_temp))
            case ('Mehl', 'NRL')
               if (.not.allocated(TB_Repuls)) then
                  allocate(TB_Rep_NRL::TB_Repuls(matter%N_KAO,matter%N_KAO)) ! make it for NRL parametrization
                  TB_Repuls%Param = ''
               endif
               TB_Repuls(i,j)%Param = trim(adjustl(ch_temp))
            case ('DFTB')
               if (.not.allocated(TB_Repuls)) then
                  allocate(TB_Rep_DFTB::TB_Repuls(matter%N_KAO,matter%N_KAO)) ! make it for DFTB parametrization
                  TB_Repuls%Param = ''
               endif
               TB_Repuls(i,j)%Param = trim(adjustl(ch_temp))
            case ('DFTB_no_repulsion', 'DFTB_no_repulsive', 'DFTB_no_rep')
               if (.not.allocated(TB_Repuls)) then
                  allocate(TB_Rep_DFTB_no::TB_Repuls(matter%N_KAO,matter%N_KAO)) ! make it for DFTB parametrization
                  TB_Repuls%Param = ''
               endif
               TB_Repuls(i,j)%Param = trim(adjustl(ch_temp))
            case ('3TB')
               if (.not.allocated(TB_Repuls)) then
                  allocate(TB_Rep_3TB::TB_Repuls(matter%N_KAO,matter%N_KAO)) ! make it for 3TB parametrization
                  TB_Repuls%Param = ''
               endif
               TB_Repuls(i,j)%Param = trim(adjustl(ch_temp))
            case ('BOP')
               if (.not.allocated(TB_Repuls)) then
                  allocate(TB_Rep_BOP::TB_Repuls(matter%N_KAO,matter%N_KAO)) ! make it for BOP parametrization
                  TB_Repuls%Param = ''
               endif
               TB_Repuls(i,j)%Param = trim(adjustl(ch_temp))
            case ('xTB')
               if (.not.allocated(TB_Repuls)) then
                  allocate(TB_Rep_xTB::TB_Repuls(matter%N_KAO,matter%N_KAO)) ! make it for xTB parametrization
                  TB_Repuls%Param = ''
               endif
               TB_Repuls(i,j)%Param = trim(adjustl(ch_temp))
            case default
               write(Error_descript,'(a,a,a,$)') 'Wrong TB-repulsive parametrization class '//trim(adjustl(ch_temp))//' specified in file '//trim(adjustl(File_name))
               call Save_error_details(Err, 4, Error_descript)
               print*, trim(adjustl(Error_descript))
               goto 3421
            end select

            ! Prior to use TB parameters, we now always have to find out which class they belong to:
            select type (TB_Repuls)
            type is (TB_Rep_Pettifor)
               Error_descript = ''
               call read_Pettifor_TB_repulsive(FN, i,j, TB_Repuls, Error_descript, INFO)
               if (INFO .NE. 0) then
                  Err%Err_descript = trim(adjustl(Error_descript))//' in file '//trim(adjustl(File_name)) 
                  call Save_error_details(Err, INFO, Err%Err_descript)
                  print*, trim(adjustl(Err%Err_descript))
                  goto 3421
               endif
            type is (TB_Rep_Molteni)
               Error_descript = ''
               call read_Molteni_TB_repulsive(FN, i,j, TB_Repuls, Error_descript, INFO)
               if (INFO .NE. 0) then
                  Err%Err_descript = trim(adjustl(Error_descript))//' in file '//trim(adjustl(File_name)) 
                  call Save_error_details(Err, INFO, Err%Err_descript)
                  print*, trim(adjustl(Err%Err_descript))
                  goto 3421
               endif
             type is (TB_Rep_Fu)
               Error_descript = ''
               call read_Fu_TB_repulsive(FN, i,j, TB_Repuls, Error_descript, INFO)
               if (INFO .NE. 0) then
                  Err%Err_descript = trim(adjustl(Error_descript))//' in file '//trim(adjustl(File_name)) 
                  call Save_error_details(Err, INFO, Err%Err_descript)
                  print*, trim(adjustl(Err%Err_descript))
                  goto 3421
               endif
            type is (TB_Rep_NRL)
               Error_descript = ''
               ! There is no repulsive part in NRL
            type is (TB_Rep_DFTB)
               Error_descript = ''
               call read_DFTB_TB_repulsive(FN, i,j, TB_Repuls, Error_descript, INFO)    ! below
               if (INFO .NE. 0) then
                  Err%Err_descript = trim(adjustl(Error_descript))//' in file '//trim(adjustl(File_name)) 
                  call Save_error_details(Err, INFO, Err%Err_descript)
                  print*, trim(adjustl(Err%Err_descript))
                  goto 3421
               endif
            type is (TB_Rep_DFTB_no)
               Error_descript = ''
               ! Nothing to read, since repulsive potential is not provided in skf-file
            type is (TB_Rep_3TB)
               Error_descript = ''
               ! There is no repulsive part in 3TB
            type is (TB_Rep_BOP)
               Error_descript = ''
               ! Nothing to do with repulsive part in BOP parameterization
            type is (TB_Rep_xTB)
               Error_descript = ''
               !call read_xTB_repulsive(FN, i, j, TB_Repuls, Error_descript, INFO)    ! module "Dealing_with_xTB"
               ! Repulsive part has already been read above together with Hamiltonian parameters
            end select
            close(FN)
            !PAUSE 'READING INPUT'
         else
            write(Error_descript,'(a,$)') 'File '//trim(adjustl(File_name))//' could not be found, the program terminates'
            call Save_error_details(Err, 1, Error_descript)
            print*, trim(adjustl(Error_descript))
            goto 3421
         endif
         
         
         !rrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrr
         ! Now read van der Waals part parametrization, if it exists:
         write(ch_temp,'(a)') trim(adjustl(matter%Atoms(i)%Name))//'_'//trim(adjustl(matter%Atoms(j)%Name))//'_'
         write(File_name, '(a,a,a)') trim(adjustl(Path)), trim(adjustl(numpar%path_sep)), trim(adjustl(ch_temp))//'TB_vdW.txt'
         inquire(file=trim(adjustl(File_name)),exist=file_exists)
         
         if (file_exists) then
            !open(NEWUNIT=FN, FILE = trim(adjustl(File_name)), status = 'old', action='READ')
            FN=108
            open(UNIT=FN, FILE = trim(adjustl(File_name)), status = 'old', action='READ')
            inquire(file=trim(adjustl(File_name)),opened=file_opened)
            if (.not.file_opened) then
               Error_descript = 'File '//trim(adjustl(File_name))//' could not be opened, the program terminates'
               call Save_error_details(Err, 2, Error_descript)
               print*, trim(adjustl(Error_descript))
               goto 3422
            endif
            count_lines = 0
            INFO = 0

            ! Read the first line to figure out which TB vdW parametrization is used for this material:
            read(FN,*,IOSTAT=Reason) ch_temp
            call read_file(Reason, count_lines, read_well)
            if (.not. read_well) then
               write(Error_descript,'(a,i5,a,$)') 'Could not read line ', count_lines, ' in file '//trim(adjustl(File_name))
               call Save_error_details(Err, 3, Error_descript)
               print*, trim(adjustl(Error_descript))
               goto 3422
            endif
            
            ! Make the TB vdW parameters of a selected class, depending on what is read in the file:
            select case (trim(adjustl(ch_temp)))
            case ('Girifalco')
               if (.not.allocated(TB_Waals)) then
                  allocate(TB_vdW_Girifalco::TB_Waals(matter%N_KAO,matter%N_KAO)) ! make it for Girifalco parametrization
                  TB_Waals%Param = ''
               endif
               TB_Waals(i,j)%Param = trim(adjustl(ch_temp))
            case ('Dumitrica') ! UNFINISHED, DO NOT USE
               if (.not.allocated(TB_Waals)) then
                  allocate(TB_vdW_Dumitrica::TB_Waals(matter%N_KAO,matter%N_KAO)) ! make it for Dumitrica parametrization
                  TB_Waals%Param = ''
               endif
               TB_Waals(i,j)%Param = trim(adjustl(ch_temp))
            case default
               write(Error_descript,'(a,a,a,$)') 'Unknown TB-vdW parametrization class '//trim(adjustl(ch_temp))//' specified in file '//trim(adjustl(File_name))
!                call Save_error_details(Err, 4, Error_descript)
               print*, trim(adjustl(Error_descript))
               print*, 'Proceeding without van der Waals forces'
               close(FN) ! close file
               goto 3422
            end select
            
            ! Prior to use TB parameters, we now always have to find out which class the belong to:
            select type (TB_Waals)
            type is (TB_vdW_Girifalco)
               Error_descript = ''
               !call read_Pettifor_TB_repulsive(FN, numpar%El_num_ij(i,j), TB_Repuls, Error_descript, INFO)
               call read_vdW_Girifalco_TB(FN, i,j, TB_Waals, Error_descript, INFO)
               if (INFO .NE. 0) then
                  Err%Err_descript = trim(adjustl(Error_descript))//' in file '//trim(adjustl(File_name)) 
                  call Save_error_details(Err, INFO, Err%Err_descript)
                  print*, trim(adjustl(Err%Err_descript))
                  goto 3422
               endif
            type is (TB_vdW_Dumitrica) ! UNFINISHED, DO NOT USE
               Error_descript = ''
               !call read_Pettifor_TB_repulsive(FN, numpar%El_num_ij(i,j), TB_Repuls, Error_descript, INFO)
               call read_vdW_Dumitrica_TB(FN, i,j, TB_Waals, Error_descript, INFO)
               if (INFO .NE. 0) then
                  Err%Err_descript = trim(adjustl(Error_descript))//' in file '//trim(adjustl(File_name)) 
                  call Save_error_details(Err, INFO, Err%Err_descript)
                  print*, trim(adjustl(Err%Err_descript))
                  goto 3422
               endif
            end select
            close(FN)
         else
            print*, 'No van der Waals file found, go on without van der Waals forces'
         endif !(file_exists)
3422     continue

         ! Now read Coulomb parameterization:
         write(ch_temp,'(a)') trim(adjustl(matter%Atoms(i)%Name))//'_'//trim(adjustl(matter%Atoms(j)%Name))//'_'
         write(File_name, '(a,a,a)') trim(adjustl(Path)), trim(adjustl(numpar%path_sep)), trim(adjustl(ch_temp))//'TB_Coulomb.txt'
         inquire(file=trim(adjustl(File_name)),exist=file_exists)
         
         if (file_exists .and. (numpar%E_work < 1d10)) then ! there can be unballanced charge, try to use Coulomb potential
            FN=109
            open(UNIT=FN, FILE = trim(adjustl(File_name)), status = 'old', action='READ')
            inquire(file=trim(adjustl(File_name)),opened=file_opened)
            if (.not.file_opened) then
               Error_descript = 'File '//trim(adjustl(File_name))//' could not be opened, the program terminates'
               call Save_error_details(Err, 2, Error_descript)
               print*, trim(adjustl(Error_descript))
               goto 3423
            endif
            count_lines = 0
            INFO = 0
            ! Read the first line to figure out which TB vdW parametrization is used for this material:
            read(FN,*,IOSTAT=Reason) ch_temp
            call read_file(Reason, count_lines, read_well)
            if (.not. read_well) then
               write(Error_descript,'(a,i5,a,$)') 'Could not read line ', count_lines, ' in file '//trim(adjustl(File_name))
               call Save_error_details(Err, 3, Error_descript)
               print*, trim(adjustl(Error_descript))
               goto 3423
            endif
            
            ! Make the Coulomb parameters of a selected class, depending on what is read in the file:
            select case (trim(adjustl(ch_temp)))
            case ('Coulomb_cut')
               if (.not.allocated(TB_Coul)) then
                  allocate(TB_Coulomb_cut::TB_Coul(matter%N_KAO,matter%N_KAO)) ! make it for Coulomb parametrization
                  TB_Coul%Param = ''
               endif
               TB_Coul(i,j)%Param = trim(adjustl(ch_temp))
            case ('Cutie') ! testing ONLY
               if (.not.allocated(TB_Coul)) then
                  allocate(Cutie::TB_Coul(matter%N_KAO,matter%N_KAO)) ! make it for Coulomb parametrization
                  TB_Coul%Param = ''                  
               endif
               TB_Coul(i,j)%Param = trim(adjustl(ch_temp))
            case default
               write(Error_descript,'(a,a,a,$)') 'Unknown Coulomb parametrization class '//trim(adjustl(ch_temp))//' specified in file '//trim(adjustl(File_name))
!                call Save_error_details(Err, 4, Error_descript)
               print*, trim(adjustl(Error_descript))
               print*, 'Proceeding without Coulomb forces from unballanced charge'
               close(FN) ! close file
               goto 3423
            end select
            
            ! Prior to use Coulomb parameters, we now always have to find out which class the belong to:
            select type (TB_Coul)
            type is (TB_Coulomb_cut)
               Error_descript = ''
               !call read_Pettifor_TB_repulsive(FN, numpar%El_num_ij(i,j), TB_Repuls, Error_descript, INFO)
               call read_Coulomb_cut_TB(FN, i,j, TB_Coul, Error_descript, INFO)
               if (INFO .NE. 0) then
                  Err%Err_descript = trim(adjustl(Error_descript))//' in file '//trim(adjustl(File_name)) 
                  call Save_error_details(Err, INFO, Err%Err_descript)
                  print*, trim(adjustl(Err%Err_descript))
                  goto 3423
               endif
               ! [N*A/e] coupling constant of Coulomb field (e/(4*Pi*e0)):
               TB_Coul(i,j)%k = g_e/(4.0d0*g_Pi*g_e0)*1.0d10
               !print*, TB_Coul(i,j)%Param, TB_Coul(i,j)%k
            end select
            close(FN)
         else
            print*, 'No Coulomb parameterization file found, or no unbalanced charge possible'
            print*, 'go on without Coulomb forces'
         endif
3423     continue
         

         ! Now read additional short-range repulsive (exponential wall) parameterization:
         write(ch_temp,'(a)') trim(adjustl(matter%Atoms(i)%Name))//'_'//trim(adjustl(matter%Atoms(j)%Name))//'_'
         write(File_name, '(a,a,a)') trim(adjustl(Path)), trim(adjustl(numpar%path_sep)), trim(adjustl(ch_temp))//'TB_wall.txt'
         inquire(file=trim(adjustl(File_name)),exist=file_exists)
         if (.not.file_exists) then ! try the new name
            write(File_name, '(a,a,a)') trim(adjustl(Path)), trim(adjustl(numpar%path_sep)), trim(adjustl(ch_temp))//'TB_short.txt'
            inquire(file=trim(adjustl(File_name)),exist=file_exists)
         endif
         ! try the other order of elements:
         if (.not.file_exists) then
            write(ch_temp,'(a)') trim(adjustl(matter%Atoms(j)%Name))//'_'//trim(adjustl(matter%Atoms(i)%Name))//'_'
            write(File_name, '(a,a,a)') trim(adjustl(Path)), trim(adjustl(numpar%path_sep)), trim(adjustl(ch_temp))//'TB_wall.txt'
            inquire(file=trim(adjustl(File_name)),exist=file_exists)
         endif
         if (.not.file_exists) then ! try the new name
            write(File_name, '(a,a,a)') trim(adjustl(Path)), trim(adjustl(numpar%path_sep)), trim(adjustl(ch_temp))//'TB_short.txt'
            inquire(file=trim(adjustl(File_name)),exist=file_exists)
         endif

         if (file_exists) then
            FN=110
            open(UNIT=FN, FILE = trim(adjustl(File_name)), status = 'old', action='READ')
            inquire(file=trim(adjustl(File_name)),opened=file_opened)
            if (.not.file_opened) then
               Error_descript = 'File '//trim(adjustl(File_name))//' could not be opened, the program terminates'
               call Save_error_details(Err, 2, Error_descript)
               print*, trim(adjustl(Error_descript))
               goto 3425
            endif
            count_lines = 0
            INFO = 0
            ! Read the first line to figure out which exponential wall parametrization is used for this material:
            read(FN,*,IOSTAT=Reason) ch_temp
            call read_file(Reason, count_lines, read_well)
            if (.not. read_well) then
               write(Error_descript,'(a,i5,a,$)') 'Could not read line ', count_lines, ' in file '//trim(adjustl(File_name))
               call Save_error_details(Err, 3, Error_descript)
               print*, trim(adjustl(Error_descript))
               goto 3425
            endif
            
            ! Make the exponential wall  parameters of a selected class, depending on what is read in the file:
            select case (trim(adjustl(ch_temp)))
            case ('Simple_wall', 'SIMPLE_WALL', 'simple_wall')
               if (.not.allocated(TB_Expwall)) then
                  allocate(TB_Exp_wall_simple::TB_Expwall(matter%N_KAO,matter%N_KAO)) ! make it for exponential wall  parametrization
                  TB_Expwall%Param = ''
               endif
               TB_Expwall(i,j)%Param = trim(adjustl(ch_temp))
               !print*, i, j, TB_Expwall(i,j)%Param, trim(adjustl(ch_temp))
            case ('General', 'general', 'GENERAL')
               if (.not.allocated(TB_Expwall)) then
                  allocate(TB_Short_Rep::TB_Expwall(matter%N_KAO,matter%N_KAO)) ! make it for exponential wall  parametrization
                  TB_Expwall%Param = ''
               endif
               TB_Expwall(i,j)%Param = trim(adjustl(ch_temp))
               !print*, i, j, TB_Expwall(i,j)%Param, trim(adjustl(ch_temp))
            case default
               write(Error_descript,'(a,a,a,$)') 'Unknown short-range (exponential wall) parametrization class '//trim(adjustl(ch_temp))//' specified in file '//trim(adjustl(File_name))
!                call Save_error_details(Err, 4, Error_descript)
               print*, trim(adjustl(Error_descript))
               print*, 'Proceeding without additional short-range (exponential wall) forces'
               close(FN) ! close file
               goto 3425
            end select
            
            ! Prior to use Exponential wall parameters, we now always have to find out which class the belong to:
            select type (TB_Expwall)
            type is (TB_Exp_wall_simple)
               Error_descript = ''
               call read_Exponential_wall_TB(FN, i,j, TB_Expwall, Error_descript, INFO)   ! below
               if (INFO .NE. 0) then
                  Err%Err_descript = trim(adjustl(Error_descript))//' in file '//trim(adjustl(File_name)) 
                  call Save_error_details(Err, INFO, Err%Err_descript)
                  print*, trim(adjustl(Err%Err_descript))
                  goto 3425
               endif
            type is (TB_Short_Rep)
               Error_descript = ''
               call read_Short_Rep_TB(FN, i,j, TB_Expwall, Error_descript, INFO)   ! below
               if (INFO .NE. 0) then
                  Err%Err_descript = trim(adjustl(Error_descript))//' in file '//trim(adjustl(File_name))
                  call Save_error_details(Err, INFO, Err%Err_descript)
                  print*, trim(adjustl(Err%Err_descript))
                  goto 3425
               endif
            end select
            close(FN)
         else
            print*, 'No exponential wall parameterization file found'
            print*, 'go on without an exponential wall at short distances'
         endif
3425     continue

      enddo do_second
   enddo do_first

   ! For 3TB parameterization, compounds requires rewriting on-site terms:
   select type (TB_Hamil)
   type is (TB_H_3TB)
      if (matter%N_KAO > 1) then
         ! [OS 0] :
!          TB_Hamil(1,1)%Hhavg = TB_Hamil(1,2)%Hhavg
!          TB_Hamil(1,1)%Hhcf = TB_Hamil(1,2)%Hhcf
!          TB_Hamil(2,2)%Hhavg = TB_Hamil(2,1)%Hhavg
!          TB_Hamil(2,2)%Hhcf = TB_Hamil(2,1)%Hhcf
         ! [OS 1] :
         TB_Hamil(1,1)%Hhavg = TB_Hamil(2,1)%Hhavg
         TB_Hamil(1,1)%Hhcf = TB_Hamil(2,1)%Hhcf
         TB_Hamil(2,2)%Hhavg = TB_Hamil(1,2)%Hhavg
         TB_Hamil(2,2)%Hhcf = TB_Hamil(1,2)%Hhcf
      endif
   endselect


3421 continue
end subroutine read_TB_parameters



subroutine read_Short_Rep_TB(FN, i,j, TB_Expwall, Error_descript, INFO)   ! below
   integer, intent(in) :: FN ! file number where to read from
   integer, intent(in) :: i, j ! numbers of pair of elements for which we read the data
   type(TB_Short_Rep), dimension(:,:), intent(inout) ::  TB_Expwall ! parameters of the exponential wall potential
   character(*), intent(out) :: Error_descript	! error save
   integer, intent(out) :: INFO	! error description
   !------------------------
   integer :: count_lines, Reason
   logical :: read_well
   character(30) :: text
   count_lines = 1
   INFO = 0

   ! Set default values:
   TB_Expwall(i,j)%f_exp%use_it = .false.       ! no exp by default
   TB_Expwall(i,j)%f_inv_exp%use_it = .false.   ! no inverse exp by default
   TB_Expwall(i,j)%f_ZBL%use_it = .false.       ! no ZBL potential by default
   TB_Expwall(i,j)%f_cut%d0 = 0.0d0 ! cut off at zero, no repulsion by default
   TB_Expwall(i,j)%f_cut%dd = 0.01d0 ! short cut-off by default

   read_well = .true.   ! to start with
   RD: do while (read_well)
      read(FN,*,IOSTAT=Reason) text
      call read_file(Reason, count_lines, read_well)
      if (.not. read_well) exit RD  ! end of file, stop reading

      call interpret_short_range_data(FN, count_lines, read_well, text, TB_Expwall(i,j), INFO, Error_descript) ! below
      if (.not. read_well) exit RD  ! end of file, stop reading
!       print*, 'o:', i, j, text, TB_Expwall(i,j)%f_inv_exp%use_it
   enddo RD
!
!    print*, i, j, TB_Expwall(:,:)%f_inv_exp%use_it
!    pause 'read_Short_Rep_TB'
end subroutine read_Short_Rep_TB


subroutine interpret_short_range_data(FN, count_lines, read_well, text, TB_Expwall, INFO, Error_descript)
   integer, intent(in) :: FN ! file number where to read from
   integer, intent(inout) :: count_lines
   logical, intent(inout) :: read_well
   character(*), intent(in) :: text
   type(TB_Short_Rep), intent(inout) ::  TB_Expwall ! parameters of the exponential wall potential
   integer, intent(inout) :: INFO   ! error description
   character(*), intent(inout) :: Error_descript   ! error save
   !-------------------------------------
   integer :: N_pow, i, Reason

   select case (trim(adjustl(text)))
   case ('CUTOFF', 'Cutoff', 'cutoff', 'CUT_OFF', 'Cut_off', 'cut_off', 'CUT-OFF', 'Cut-off', 'cut-off', 'FERMI', 'Fermi', 'fermi')
      read(FN,*,IOSTAT=Reason) TB_Expwall%f_cut%d0, TB_Expwall%f_cut%dd
      call read_file(Reason, count_lines, read_well)
      if (.not. read_well) then
         write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
         INFO = 3
         return   ! exit the function if there is nothing else to do
      endif

   case ('EXP', 'Exp', 'exp', 'Exponential', 'exponential', 'EXPONENTIAL')
      TB_Expwall%f_exp%use_it = .true.
      read(FN,*,IOSTAT=Reason) TB_Expwall%f_exp%Phi, TB_Expwall%f_exp%r0, TB_Expwall%f_exp%a
      call read_file(Reason, count_lines, read_well)
      if (.not. read_well) then
         TB_Expwall%f_exp%use_it = .false. ! not to use
         write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
         INFO = 3
         return   ! exit the function if there is nothing else to do
      endif

   case ('INVEXP', 'InvExp', 'invexp', 'Invexp', 'INV_EXP', 'Inv_Exp', 'Inv_exp', 'inv_exp')
      TB_Expwall%f_inv_exp%use_it = .true.
      read(FN,*,IOSTAT=Reason) TB_Expwall%f_inv_exp%C, TB_Expwall%f_inv_exp%r0
      call read_file(Reason, count_lines, read_well)
      if (.not. read_well) then
         TB_Expwall%f_inv_exp%use_it = .false.   ! not to use
         write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
         INFO = 3
         return   ! exit the function if there is nothing else to do
      endif

   case ('POWER', 'Power', 'power', 'POW', 'Pow', 'pow')
      read(FN,*,IOSTAT=Reason) N_pow   ! number of power-functions
      allocate(TB_Expwall%f_pow(N_pow))
      TB_Expwall%f_pow(:)%use_it = .true.
      do i = 1, N_pow   ! read for all functions
         read(FN,*,IOSTAT=Reason) TB_Expwall%f_pow(i)%Phi, TB_Expwall%f_pow(i)%r0, TB_Expwall%f_pow(i)%m
!          print*, TB_Expwall%f_pow%Phi, TB_Expwall%f_pow%r0, TB_Expwall%f_pow%m
         call read_file(Reason, count_lines, read_well)
         if (.not. read_well) then
            deallocate(TB_Expwall%f_pow)   ! not to use
            write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
            INFO = 3
            return   ! exit the function if there is nothing else to do
         endif
      enddo

   case ('ZBL', 'zbl')
      TB_Expwall%f_ZBL%use_it = .true.

   end select
end subroutine interpret_short_range_data



subroutine read_Exponential_wall_TB(FN, i,j, TB_Expwall, Error_descript, INFO)
   integer, intent(in) :: FN ! file number where to read from
   integer, intent(in) :: i, j ! numbers of pair of elements for which we read the data
   type(TB_Exp_wall_simple), dimension(:,:), intent(inout) ::  TB_Expwall ! parameters of the exponential wall potential
   character(*), intent(out) :: Error_descript	! error save
   integer, intent(out) :: INFO	! error description
   integer count_lines, Reason
   logical read_well
   count_lines = 1

   read(FN,*,IOSTAT=Reason) TB_Expwall(i,j)%C
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3426
   endif

   read(FN,*,IOSTAT=Reason) TB_Expwall(i,j)%r0
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3426
   endif

   read(FN,*,IOSTAT=Reason) TB_Expwall(i,j)%d0
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3426
   endif

   read(FN,*,IOSTAT=Reason) TB_Expwall(i,j)%dd
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3426
   endif
   
3426 continue
end subroutine read_Exponential_wall_TB




subroutine read_Coulomb_cut_TB(FN, i,j, TB_Coul, Error_descript, INFO)
   integer, intent(in) :: FN ! file number where to read from
   integer, intent(in) :: i, j ! numbers of pair of elements for which we read the data
   type(TB_Coulomb_cut), dimension(:,:), intent(inout) ::  TB_Coul ! parameters of the Hamiltonian of TB
   character(*), intent(out) :: Error_descript	! error save
   integer, intent(out) :: INFO	! error description
   integer count_lines, Reason
   logical read_well
   count_lines = 1

   read(FN,*,IOSTAT=Reason) TB_Coul(i,j)%dm
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3424
   endif

   read(FN,*,IOSTAT=Reason) TB_Coul(i,j)%dd
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3424
   endif

3424 continue
end subroutine read_Coulomb_cut_TB



subroutine read_vdW_Girifalco_TB(FN, i,j, TB_Waals, Error_descript, INFO)
   integer, intent(in) :: FN ! file number where to read from
   integer, intent(in) :: i, j ! numbers of pair of elements for which we read the data
   type(TB_vdW_Girifalco), dimension(:,:), intent(inout) ::  TB_Waals ! parameters of the Hamiltonian of TB
   character(*), intent(out) :: Error_descript	! error save
   integer, intent(out) :: INFO	! error description
   integer count_lines, Reason
   logical read_well
   count_lines = 1
   
   read(FN,*,IOSTAT=Reason) TB_Waals(i,j)%C12
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3423
   endif
   
   read(FN,*,IOSTAT=Reason) TB_Waals(i,j)%C6
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3423
   endif
   
!    read(FN,*,IOSTAT=Reason) TB_Waals(i,j)%r_L
!    call read_file(Reason, count_lines, read_well)
!    if (.not. read_well) then
!       write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
!       INFO = 3
!       goto 3423
!    endif
!    
!    read(FN,*,IOSTAT=Reason) TB_Waals(i,j)%d_L
!    call read_file(Reason, count_lines, read_well)
!    if (.not. read_well) then
!       write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
!       INFO = 3
!       goto 3423
!    endif
! 
!    read(FN,*,IOSTAT=Reason) TB_Waals(i,j)%r_S
!    call read_file(Reason, count_lines, read_well)
!    if (.not. read_well) then
!       write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
!       INFO = 3
!       goto 3423
!    endif
!    
!    read(FN,*,IOSTAT=Reason) TB_Waals(i,j)%d_S
!    call read_file(Reason, count_lines, read_well)
!    if (.not. read_well) then
!       write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
!       INFO = 3
!       goto 3423
!    endif
! 
!    read(FN,*,IOSTAT=Reason) TB_Waals(i,j)%r_LJ
!    call read_file(Reason, count_lines, read_well)
!    if (.not. read_well) then
!       write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
!       INFO = 3
!       goto 3423
!    endif
   
   read(FN,*,IOSTAT=Reason) TB_Waals(i,j)%dm
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3423
   endif

   read(FN,*,IOSTAT=Reason) TB_Waals(i,j)%d_cut
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3423
   endif
   
   read(FN,*,IOSTAT=Reason) TB_Waals(i,j)%a
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3423
   endif
   
   read(FN,*,IOSTAT=Reason) TB_Waals(i,j)%b
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3423
   endif
   
   read(FN,*,IOSTAT=Reason) TB_Waals(i,j)%c
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3423
   endif
   
   read(FN,*,IOSTAT=Reason) TB_Waals(i,j)%d
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3423
   endif
   
   read(FN,*,IOSTAT=Reason) TB_Waals(i,j)%dsm
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3423
   endif
   
   read(FN,*,IOSTAT=Reason) TB_Waals(i,j)%ds_cut
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3423
   endif
   
   read(FN,*,IOSTAT=Reason) TB_Waals(i,j)%as
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3423
   endif
   
   read(FN,*,IOSTAT=Reason) TB_Waals(i,j)%bs
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3423
   endif
   
   read(FN,*,IOSTAT=Reason) TB_Waals(i,j)%cs
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3423
   endif

   read(FN,*,IOSTAT=Reason) TB_Waals(i,j)%ds
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3423
   endif
   
   read(FN,*,IOSTAT=Reason) TB_Waals(i,j)%es
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3423
   endif
   
   read(FN,*,IOSTAT=Reason) TB_Waals(i,j)%fs
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3423
   endif
   
!    print*, TB_Waals(i,j)
!    pause

3423 continue
end subroutine read_vdW_Girifalco_TB


subroutine read_vdW_Dumitrica_TB(FN, i,j, TB_Waals, Error_descript, INFO)
   integer, intent(in) :: FN ! file number where to read from
   integer, intent(in) :: i, j ! numbers of pair of elements for which we read the data
   type(TB_vdW_Dumitrica), dimension(:,:), intent(inout) ::  TB_Waals ! parameters of the Hamiltonian of TB
   character(*), intent(out) :: Error_descript	! error save
   integer, intent(out) :: INFO	! error description
   integer count_lines, Reason
   logical read_well
   count_lines = 1

   read(FN,*,IOSTAT=Reason) TB_Waals(i,j)%C6
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3423
   endif

   read(FN,*,IOSTAT=Reason) TB_Waals(i,j)%alpha
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3423
   endif
   
3423 continue
end subroutine read_vdW_Dumitrica_TB



subroutine read_Molteni_TB_repulsive(FN, i,j, TB_Repuls, Error_descript, INFO)
   integer, intent(in) :: FN ! file number where to read from
   integer, intent(in) :: i, j ! numbers of pair of elements for which we read the data
   type(TB_Rep_Molteni), dimension(:,:), intent(inout) ::  TB_Repuls ! parameters of the Hamiltonian of TB
   character(*), intent(out) :: Error_descript	! error save
   integer, intent(out) :: INFO	! error description
   integer count_lines, Reason
   logical read_well
   count_lines = 1

   ! Read the repulsive parameters of TB:
   read(FN,*,IOSTAT=Reason) TB_Repuls(i,j)%NP
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3423
   endif

   select case (TB_Repuls(i,j)%NP)
   case (1:2) ! Molteni
      call read_Molteni_repuls(FN, TB_Repuls, i, j, read_well, count_lines, Reason, Error_descript, INFO)
   case default ! Allen
      call read_Allen_repuls(FN, TB_Repuls, i, j, read_well, count_lines, Reason, Error_descript, INFO)
   end select


3423 continue
end subroutine read_Molteni_TB_repulsive


subroutine read_Allen_repuls(FN, TB_Repuls, i, j, read_well, count_lines, Reason, Error_descript, INFO)
   integer, intent(in) :: FN ! file number where to read from
   integer, intent(in) :: i, j ! numbers of pair of elements for which we read the data
   type(TB_Rep_Molteni), dimension(:,:), intent(inout) ::  TB_Repuls ! parameters of the Hamiltonian of TB
   logical, intent(inout) :: read_well
   integer, intent(inout) :: count_lines, Reason
   character(*), intent(out) :: Error_descript	! error save
   integer, intent(out) :: INFO	! error description

   read(FN,*,IOSTAT=Reason) TB_Repuls(i,j)%a
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3423
   endif

   read(FN,*,IOSTAT=Reason) TB_Repuls(i,j)%b
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3423
   endif

   read(FN,*,IOSTAT=Reason) TB_Repuls(i,j)%c
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3423
   endif

  read(FN,*,IOSTAT=Reason) TB_Repuls(i,j)%r0
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3423
   endif

   read(FN,*,IOSTAT=Reason) TB_Repuls(i,j)%rcut
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3423
   endif
   TB_Repuls(i,j)%rcut = TB_Repuls(i,j)%rcut*TB_Repuls(i,j)%r0

   read(FN,*,IOSTAT=Reason) TB_Repuls(i,j)%d
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3423
   endif

   3423 continue
end subroutine read_Allen_repuls



subroutine read_Molteni_repuls(FN, TB_Repuls, i, j, read_well, count_lines, Reason, Error_descript, INFO)
   integer, intent(in) :: FN ! file number where to read from
   integer, intent(in) :: i, j ! numbers of pair of elements for which we read the data
   type(TB_Rep_Molteni), dimension(:,:), intent(inout) ::  TB_Repuls ! parameters of the Hamiltonian of TB
   logical, intent(inout) :: read_well
   integer, intent(inout) :: count_lines, Reason
   character(*), intent(out) :: Error_descript	! error save
   integer, intent(out) :: INFO	! error description

   read(FN,*,IOSTAT=Reason) TB_Repuls(i,j)%phi1
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3423
   endif

   read(FN,*,IOSTAT=Reason) TB_Repuls(i,j)%phi2
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3423
   endif

   read(FN,*,IOSTAT=Reason) TB_Repuls(i,j)%r0
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3423
   endif

   read(FN,*,IOSTAT=Reason) TB_Repuls(i,j)%rcut
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3423
   endif
   TB_Repuls(i,j)%rcut = TB_Repuls(i,j)%rcut*TB_Repuls(i,j)%r0

   read(FN,*,IOSTAT=Reason) TB_Repuls(i,j)%d
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3423
   endif

   select case (TB_Repuls(i,j)%NP)
   case (2) ! rational:
      read(FN,*,IOSTAT=Reason) TB_Repuls(i,j)%m
   case default ! exp:
      read(FN,*,IOSTAT=Reason) TB_Repuls(i,j)%alpha
   end select
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3423
   endif

   3423 continue
end subroutine read_Molteni_repuls


subroutine read_Pettifor_TB_repulsive(FN, i, j, TB_Repuls, Error_descript, INFO)
   integer, intent(in) :: FN ! file number where to read from
   integer, intent(in) :: i, j ! numbers of pair of elements for which we read the data
   type(TB_Rep_Pettifor), dimension(:,:), intent(inout) ::  TB_Repuls ! parameters of the Hamiltonian of TB
   character(*), intent(out) :: Error_descript	! error save
   integer, intent(out) :: INFO	! error description
   integer count_lines, Reason
   logical read_well
   count_lines = 1

   ! Read the repulsive parameters of TB:
   read(FN,*,IOSTAT=Reason) TB_Repuls(i,j)%E0_TB
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3423
   endif

   read(FN,*,IOSTAT=Reason) TB_Repuls(i,j)%phi0
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3423
   endif

   read(FN,*,IOSTAT=Reason) TB_Repuls(i,j)%m
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3423
   endif

   read(FN,*,IOSTAT=Reason) TB_Repuls(i,j)%mc
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3423
   endif

   read(FN,*,IOSTAT=Reason) TB_Repuls(i,j)%d0
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3423
   endif

   read(FN,*,IOSTAT=Reason) TB_Repuls(i,j)%d1
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3423
   endif

   read(FN,*,IOSTAT=Reason) TB_Repuls(i,j)%dm
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3423
   endif

   read(FN,*,IOSTAT=Reason) TB_Repuls(i,j)%dc
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3423
   endif

   read(FN,*,IOSTAT=Reason) TB_Repuls(i,j)%c0(1)
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3423
   endif

   read(FN,*,IOSTAT=Reason) TB_Repuls(i,j)%c0(2)
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3423
   endif

   read(FN,*,IOSTAT=Reason) TB_Repuls(i,j)%c0(3)
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3423
   endif

   read(FN,*,IOSTAT=Reason) TB_Repuls(i,j)%c0(4)
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3423
   endif

   read(FN,*,IOSTAT=Reason) TB_Repuls(i,j)%a0(1)
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3423
   endif

   read(FN,*,IOSTAT=Reason) TB_Repuls(i,j)%a0(2)
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3423
   endif

   read(FN,*,IOSTAT=Reason) TB_Repuls(i,j)%a0(3)
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3423
   endif

   read(FN,*,IOSTAT=Reason) TB_Repuls(i,j)%a0(4)
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3423
   endif

   read(FN,*,IOSTAT=Reason) TB_Repuls(i,j)%a0(5)
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3423
   endif

3423 continue
end subroutine read_Pettifor_TB_repulsive



subroutine read_Fu_TB_repulsive(FN, i, j, TB_Repuls, Error_descript, INFO)
   integer, intent(in) :: FN ! file number where to read from
   integer, intent(in) :: i, j ! numbers of pair of elements for which we read the data
   type(TB_Rep_Fu), dimension(:,:), intent(inout) ::  TB_Repuls ! parameters of the Hamiltonian of TB
   character(*), intent(out) :: Error_descript	! error save
   integer, intent(out) :: INFO	! error description
   integer count_lines, Reason
   logical read_well
   count_lines = 1

   ! Read the repulsive parameters of TB:
   read(FN,*,IOSTAT=Reason) TB_Repuls(i,j)%E0_TB
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3423
   endif

   read(FN,*,IOSTAT=Reason) TB_Repuls(i,j)%phi0
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3423
   endif

   read(FN,*,IOSTAT=Reason) TB_Repuls(i,j)%m
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3423
   endif

   read(FN,*,IOSTAT=Reason) TB_Repuls(i,j)%mc
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3423
   endif

   read(FN,*,IOSTAT=Reason) TB_Repuls(i,j)%d0
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3423
   endif

   read(FN,*,IOSTAT=Reason) TB_Repuls(i,j)%d1
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3423
   endif

   read(FN,*,IOSTAT=Reason) TB_Repuls(i,j)%dm
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3423
   endif

   read(FN,*,IOSTAT=Reason) TB_Repuls(i,j)%dc
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3423
   endif

   read(FN,*,IOSTAT=Reason) TB_Repuls(i,j)%c0(1)
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3423
   endif

   read(FN,*,IOSTAT=Reason) TB_Repuls(i,j)%c0(2)
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3423
   endif

   read(FN,*,IOSTAT=Reason) TB_Repuls(i,j)%c0(3)
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3423
   endif

   read(FN,*,IOSTAT=Reason) TB_Repuls(i,j)%c0(4)
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3423
   endif

   read(FN,*,IOSTAT=Reason) TB_Repuls(i,j)%a0(1)
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3423
   endif

   read(FN,*,IOSTAT=Reason) TB_Repuls(i,j)%a0(2)
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3423
   endif

   read(FN,*,IOSTAT=Reason) TB_Repuls(i,j)%a0(3)
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3423
   endif

   read(FN,*,IOSTAT=Reason) TB_Repuls(i,j)%a0(4)
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3423
   endif

   read(FN,*,IOSTAT=Reason) TB_Repuls(i,j)%a0(5)
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3423
   endif

   read(FN,*,IOSTAT=Reason) TB_Repuls(i,j)%C_a
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3423
   endif
3423 continue
end subroutine read_Fu_TB_repulsive


subroutine read_DFTB_TB_repulsive(FN, i,j, TB_Repuls, Error_descript, INFO)
   integer, intent(in) :: FN ! file number where to read from
   integer, intent(in) :: i, j ! numbers of pair of elements for which we read the data
   type(TB_Rep_DFTB), dimension(:,:), intent(inout) ::  TB_Repuls ! parameters of the Hamiltonian of TB
   character(*), intent(out) :: Error_descript	! error save
   integer, intent(out) :: INFO	! error description
   integer count_lines, Reason
   logical read_well
   count_lines = 1

   ! Skip first line as it are already defined within the Hamiltonian file
   read(FN,*,IOSTAT=Reason)
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3415
   endif

   read(FN,*,IOSTAT=Reason) TB_Repuls(i,j)%ToP   ! type of parameterization: 0=polinomial, 1=spline
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3415
   endif
   
3415 continue
end subroutine read_DFTB_TB_repulsive


!------------------------------------------------------------
subroutine read_Molteni_TB_Hamiltonian(FN, i,j, TB_Hamil, Error_descript, INFO)
   integer, intent(in) :: FN ! file number where to read from
   integer, intent(in) :: i, j  ! numbers of pair of elements for which we read the data
   type(TB_H_Molteni), dimension(:,:), intent(inout) ::  TB_Hamil ! parameters of the Hamiltonian of TB
   character(*), intent(out) :: Error_descript	! error save
   integer, intent(out) :: INFO	! error description
   integer count_lines, Reason
   logical read_well
   count_lines = 1

   ! Read the Hamiltonian parameters of TB:
   read(FN,*,IOSTAT=Reason) TB_Hamil(i,j)%Es
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3422
   endif

   read(FN,*,IOSTAT=Reason) TB_Hamil(i,j)%Ep
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3422
   endif

   read(FN,*,IOSTAT=Reason) TB_Hamil(i,j)%Esa
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3422
   endif

   read(FN,*,IOSTAT=Reason) TB_Hamil(i,j)%V0(1)
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3422
   endif

   read(FN,*,IOSTAT=Reason) TB_Hamil(i,j)%V0(2)
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3422
   endif

   read(FN,*,IOSTAT=Reason) TB_Hamil(i,j)%V0(3)
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3422
   endif

   read(FN,*,IOSTAT=Reason) TB_Hamil(i,j)%V0(4)
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3422
   endif

   read(FN,*,IOSTAT=Reason) TB_Hamil(i,j)%V0(5)
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3422
   endif

   read(FN,*,IOSTAT=Reason) TB_Hamil(i,j)%r0
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3422
   endif

   read(FN,*,IOSTAT=Reason) TB_Hamil(i,j)%n
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3422
   endif

   read(FN,*,IOSTAT=Reason) TB_Hamil(i,j)%rc
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3422
   endif

   read(FN,*,IOSTAT=Reason) TB_Hamil(i,j)%nc
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3422
   endif

   read(FN,*,IOSTAT=Reason) TB_Hamil(i,j)%rcut
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3422
   endif
   TB_Hamil(i,j)%rcut = TB_Hamil(i,j)%rcut*TB_Hamil(i,j)%r0

   read(FN,*,IOSTAT=Reason) TB_Hamil(i,j)%d
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3422
   endif
3422 continue
end subroutine read_Molteni_TB_Hamiltonian


subroutine read_Pettifor_TB_Hamiltonian(FN, i,j, TB_Hamil, Error_descript, INFO)
   integer, intent(in) :: FN ! file number where to read from
   integer, intent(in) :: i, j  ! numbers of pair of elements for which we read the data
   type(TB_H_Pettifor), dimension(:,:), intent(inout) ::  TB_Hamil ! parameters of the Hamiltonian of TB
   character(*), intent(out) :: Error_descript	! error save
   integer, intent(out) :: INFO	! error description
   integer count_lines, Reason
   logical read_well
   count_lines = 1

   ! Read the Hamiltonian parameters of TB:
   read(FN,*,IOSTAT=Reason) TB_Hamil(i,j)%Es
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3422
   endif

   read(FN,*,IOSTAT=Reason) TB_Hamil(i,j)%Ep
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3422
   endif

   read(FN,*,IOSTAT=Reason) TB_Hamil(i,j)%V0(1)
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3422
   endif

   read(FN,*,IOSTAT=Reason) TB_Hamil(i,j)%V0(2)
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3422
   endif

   read(FN,*,IOSTAT=Reason) TB_Hamil(i,j)%V0(3)
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3422
   endif

   read(FN,*,IOSTAT=Reason) TB_Hamil(i,j)%V0(4)
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3422
   endif

   read(FN,*,IOSTAT=Reason) TB_Hamil(i,j)%r0
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3422
   endif

   read(FN,*,IOSTAT=Reason) TB_Hamil(i,j)%n
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3422
   endif

   read(FN,*,IOSTAT=Reason) TB_Hamil(i,j)%r1
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3422
   endif

   read(FN,*,IOSTAT=Reason) TB_Hamil(i,j)%rm 
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3422
   endif

   read(FN,*,IOSTAT=Reason) TB_Hamil(i,j)%nc(1)
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3422
   endif

   read(FN,*,IOSTAT=Reason) TB_Hamil(i,j)%nc(2)
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3422
   endif

   read(FN,*,IOSTAT=Reason) TB_Hamil(i,j)%nc(3)
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3422
   endif

   read(FN,*,IOSTAT=Reason) TB_Hamil(i,j)%nc(4)
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3422
   endif

   read(FN,*,IOSTAT=Reason) TB_Hamil(i,j)%rc(1)
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3422
   endif

   read(FN,*,IOSTAT=Reason) TB_Hamil(i,j)%rc(2)
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3422
   endif

   read(FN,*,IOSTAT=Reason) TB_Hamil(i,j)%rc(3)
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3422
   endif

   read(FN,*,IOSTAT=Reason) TB_Hamil(i,j)%rc(4)
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3422
   endif

   read(FN,*,IOSTAT=Reason) TB_Hamil(i,j)%c0(1)
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3422
   endif

   read(FN,*,IOSTAT=Reason) TB_Hamil(i,j)%c1(1)
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3422
   endif

   read(FN,*,IOSTAT=Reason) TB_Hamil(i,j)%c2(1)
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3422
   endif

   read(FN,*,IOSTAT=Reason) TB_Hamil(i,j)%c3(1)
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3422
   endif

   read(FN,*,IOSTAT=Reason) TB_Hamil(i,j)%c0(2)
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3422
   endif

   read(FN,*,IOSTAT=Reason) TB_Hamil(i,j)%c1(2)
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3422
   endif

   read(FN,*,IOSTAT=Reason) TB_Hamil(i,j)%c2(2)
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3422
   endif

   read(FN,*,IOSTAT=Reason) TB_Hamil(i,j)%c3(2)
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3422
   endif

   read(FN,*,IOSTAT=Reason) TB_Hamil(i,j)%c0(3)
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3422
   endif

   read(FN,*,IOSTAT=Reason) TB_Hamil(i,j)%c1(3)
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3422
   endif

   read(FN,*,IOSTAT=Reason) TB_Hamil(i,j)%c2(3)
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3422
   endif

   read(FN,*,IOSTAT=Reason) TB_Hamil(i,j)%c3(3)
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3422
   endif

   read(FN,*,IOSTAT=Reason) TB_Hamil(i,j)%c0(4)
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3422
   endif

   read(FN,*,IOSTAT=Reason) TB_Hamil(i,j)%c1(4)
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3422
   endif

   read(FN,*,IOSTAT=Reason) TB_Hamil(i,j)%c2(4)
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3422
   endif

   read(FN,*,IOSTAT=Reason) TB_Hamil(i,j)%c3(4)
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3422
   endif

3422 continue
end subroutine read_Pettifor_TB_Hamiltonian



subroutine read_Fu_TB_Hamiltonian(FN, i,j, TB_Hamil, Error_descript, INFO)
   integer, intent(in) :: FN ! file number where to read from
   integer, intent(in) :: i, j  ! numbers of pair of elements for which we read the data
   type(TB_H_Fu), dimension(:,:), intent(inout) ::  TB_Hamil ! parameters of the Hamiltonian of TB
   character(*), intent(out) :: Error_descript	! error save
   integer, intent(out) :: INFO	! error description
   integer count_lines, Reason
   logical read_well
   count_lines = 1

   ! Read the Hamiltonian parameters of TB:
   read(FN,*,IOSTAT=Reason) TB_Hamil(i,j)%Es
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3422
   endif

   read(FN,*,IOSTAT=Reason) TB_Hamil(i,j)%Ep
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3422
   endif

   read(FN,*,IOSTAT=Reason) TB_Hamil(i,j)%V0(1)
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3422
   endif

   read(FN,*,IOSTAT=Reason) TB_Hamil(i,j)%V0(2)
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3422
   endif

   read(FN,*,IOSTAT=Reason) TB_Hamil(i,j)%V0(3)
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3422
   endif

   read(FN,*,IOSTAT=Reason) TB_Hamil(i,j)%V0(4)
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3422
   endif

   read(FN,*,IOSTAT=Reason) TB_Hamil(i,j)%r0
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3422
   endif

   read(FN,*,IOSTAT=Reason) TB_Hamil(i,j)%n
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3422
   endif

   read(FN,*,IOSTAT=Reason) TB_Hamil(i,j)%r1
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3422
   endif

   read(FN,*,IOSTAT=Reason) TB_Hamil(i,j)%rm 
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3422
   endif

   read(FN,*,IOSTAT=Reason) TB_Hamil(i,j)%nc(1)
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3422
   endif

   read(FN,*,IOSTAT=Reason) TB_Hamil(i,j)%nc(2)
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3422
   endif

   read(FN,*,IOSTAT=Reason) TB_Hamil(i,j)%nc(3)
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3422
   endif

   read(FN,*,IOSTAT=Reason) TB_Hamil(i,j)%nc(4)
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3422
   endif

   read(FN,*,IOSTAT=Reason) TB_Hamil(i,j)%rc(1)
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3422
   endif

   read(FN,*,IOSTAT=Reason) TB_Hamil(i,j)%rc(2)
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3422
   endif

   read(FN,*,IOSTAT=Reason) TB_Hamil(i,j)%rc(3)
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3422
   endif

   read(FN,*,IOSTAT=Reason) TB_Hamil(i,j)%rc(4)
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3422
   endif

   read(FN,*,IOSTAT=Reason) TB_Hamil(i,j)%c0(1)
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3422
   endif

   read(FN,*,IOSTAT=Reason) TB_Hamil(i,j)%c1(1)
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3422
   endif

   read(FN,*,IOSTAT=Reason) TB_Hamil(i,j)%c2(1)
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3422
   endif

   read(FN,*,IOSTAT=Reason) TB_Hamil(i,j)%c3(1)
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3422
   endif

   read(FN,*,IOSTAT=Reason) TB_Hamil(i,j)%c0(2)
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3422
   endif

   read(FN,*,IOSTAT=Reason) TB_Hamil(i,j)%c1(2)
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3422
   endif

   read(FN,*,IOSTAT=Reason) TB_Hamil(i,j)%c2(2)
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3422
   endif

   read(FN,*,IOSTAT=Reason) TB_Hamil(i,j)%c3(2)
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3422
   endif

   read(FN,*,IOSTAT=Reason) TB_Hamil(i,j)%c0(3)
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3422
   endif

   read(FN,*,IOSTAT=Reason) TB_Hamil(i,j)%c1(3)
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3422
   endif

   read(FN,*,IOSTAT=Reason) TB_Hamil(i,j)%c2(3)
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3422
   endif

   read(FN,*,IOSTAT=Reason) TB_Hamil(i,j)%c3(3)
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3422
   endif

   read(FN,*,IOSTAT=Reason) TB_Hamil(i,j)%c0(4)
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3422
   endif

   read(FN,*,IOSTAT=Reason) TB_Hamil(i,j)%c1(4)
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3422
   endif

   read(FN,*,IOSTAT=Reason) TB_Hamil(i,j)%c2(4)
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3422
   endif

   read(FN,*,IOSTAT=Reason) TB_Hamil(i,j)%c3(4)
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3422
   endif

   read(FN,*,IOSTAT=Reason) TB_Hamil(i,j)%C_a
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3422
   endif

3422 continue

end subroutine read_Fu_TB_Hamiltonian




subroutine read_Mehl_TB_Hamiltonian(FN, i,j, TB_Hamil, Error_descript, INFO)
   integer, intent(in) :: FN ! file number where to read from
   integer, intent(in) :: i, j  ! numbers of pair of elements for which we read the data
   type(TB_H_NRL), dimension(:,:), intent(inout) ::  TB_Hamil ! parameters of the Hamiltonian of TB
   character(*), intent(out) :: Error_descript	! error save
   integer, intent(out) :: INFO	! error description
   integer count_lines, Reason, i_cur, ind
   logical read_well
   count_lines = 1

   ! Read the Hamiltonian parameters of TB:
   read(FN,*,IOSTAT=Reason) TB_Hamil(i,j)%ind_split, TB_Hamil(i,j)%ind_overlap, ind
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3425
   endif
   
   read(FN,*,IOSTAT=Reason) TB_Hamil(i,j)%Rc, TB_Hamil(i,j)%lden
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3425
   endif

   read(FN,*,IOSTAT=Reason) TB_Hamil(i,j)%lambd
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
      INFO = 3
      goto 3425
   endif
   
   
   do i_cur = 1, 3	! s, p or d states
      read(FN,*,IOSTAT=Reason) TB_Hamil(i,j)%al(i_cur)
      call read_file(Reason, count_lines, read_well)
      if (.not. read_well) then
         write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
         INFO = 3
         goto 3425
      endif
   
      read(FN,*,IOSTAT=Reason) TB_Hamil(i,j)%bl(i_cur)
      call read_file(Reason, count_lines, read_well)
      if (.not. read_well) then
         write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
         INFO = 3
         goto 3425
      endif
   
      read(FN,*,IOSTAT=Reason) TB_Hamil(i,j)%cl(i_cur)
      call read_file(Reason, count_lines, read_well)
      if (.not. read_well) then
         write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
         INFO = 3
         goto 3425
      endif
   
      read(FN,*,IOSTAT=Reason) TB_Hamil(i,j)%dl(i_cur)
      call read_file(Reason, count_lines, read_well)
      if (.not. read_well) then
         write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
         INFO = 3
         goto 3425
      endif
   enddo
   
   TB_Hamil(i,j)%al(4) = 0.0d0
   TB_Hamil(i,j)%bl(4) = 0.0d0
   TB_Hamil(i,j)%cl(4) = 0.0d0
   TB_Hamil(i,j)%dl(4) = 0.0d0
   select case (TB_Hamil(i,j)%ind_split)	! in case ther eis splitting of d states into t2g and e2:
   case (1)	! there is splitting
      read(FN,*,IOSTAT=Reason) TB_Hamil(i,j)%al(4)
      call read_file(Reason, count_lines, read_well)
      if (.not. read_well) then
         write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
         INFO = 3
         goto 3425
      endif
   
      read(FN,*,IOSTAT=Reason) TB_Hamil(i,j)%bl(4)
      call read_file(Reason, count_lines, read_well)
      if (.not. read_well) then
         write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
         INFO = 3
         goto 3425
      endif
   
      read(FN,*,IOSTAT=Reason) TB_Hamil(i,j)%cl(4)
      call read_file(Reason, count_lines, read_well)
      if (.not. read_well) then
         write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
         INFO = 3
         goto 3425
      endif
   
      read(FN,*,IOSTAT=Reason) TB_Hamil(i,j)%dl(4)
      call read_file(Reason, count_lines, read_well)
      if (.not. read_well) then
         write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
         INFO = 3
         goto 3425
      endif
   case default
      ! There is no splitting
   end select
   
   
   do i_cur = 1, 10	! all states (ss sigma) thru (dd delta)
      read(FN,*,IOSTAT=Reason) TB_Hamil(i,j)%ellm(i_cur)
      call read_file(Reason, count_lines, read_well)
      if (.not. read_well) then
         write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
         INFO = 3
         goto 3425
      endif
   
      read(FN,*,IOSTAT=Reason) TB_Hamil(i,j)%fllm(i_cur)
      call read_file(Reason, count_lines, read_well)
      if (.not. read_well) then
         write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
         INFO = 3
         goto 3425
      endif
   
      if (ind <= 0) then
         TB_Hamil(i,j)%gllm(i_cur) = 0.0d0
      else 	! the variable is not zero
         read(FN,*,IOSTAT=Reason) TB_Hamil(i,j)%gllm(i_cur)
         call read_file(Reason, count_lines, read_well)
         if (.not. read_well) then
            write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
            INFO = 3
            goto 3425
         endif
      endif
      
      read(FN,*,IOSTAT=Reason) TB_Hamil(i,j)%hllm(i_cur)
      call read_file(Reason, count_lines, read_well)
      if (.not. read_well) then
         write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
         INFO = 3
         goto 3425
      endif
   enddo
   
   
   do i_cur = 1, 10	! all states (ss sigma) thru (dd delta)
      read(FN,*,IOSTAT=Reason) TB_Hamil(i,j)%pllm(i_cur)
      call read_file(Reason, count_lines, read_well)
      if (.not. read_well) then
         write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
         INFO = 3
         goto 3425
      endif
   
      read(FN,*,IOSTAT=Reason) TB_Hamil(i,j)%qllm(i_cur)
      call read_file(Reason, count_lines, read_well)
      if (.not. read_well) then
         write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
         INFO = 3
         goto 3425
      endif
   
      if (ind <= 0) then
         TB_Hamil(i,j)%rllm(i_cur) = 0.0d0
      else 	! the variable is not zero
         read(FN,*,IOSTAT=Reason) TB_Hamil(i,j)%rllm(i_cur)
         call read_file(Reason, count_lines, read_well)
         if (.not. read_well) then
            write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
            INFO = 3
            goto 3425
         endif
      endif
      
      read(FN,*,IOSTAT=Reason) TB_Hamil(i,j)%sllm(i_cur)
      call read_file(Reason, count_lines, read_well)
      if (.not. read_well) then
         write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
         INFO = 3
         goto 3425
      endif
   enddo
   
!    
!    print*, TB_Hamil(i,j)
!    
!    PAUSE 'read_Mehl_TB_Hamiltonian'
   
   3425 continue
end subroutine read_Mehl_TB_Hamiltonian



subroutine read_DFTB_TB_Params(FN, i,j, TB_Hamil, TB_Repuls, numpar, matter, Error_descript, INFO)
   integer, intent(in) :: FN ! file number where to read from
   integer, intent(in) :: i, j  ! numbers of pair of elements for which we read the data
   type(TB_H_DFTB), dimension(:,:), intent(inout) ::  TB_Hamil ! parameters of the Hamiltonian of TB
   type(TB_Rep_DFTB), dimension(:,:), intent(inout) ::  TB_Repuls ! parameters of the Hamiltonian of TB
   type(Numerics_param), intent(inout) :: numpar 	! all numerical parameters
   type(Solid), intent(in) :: matter	! all material parameters
   character(*), intent(out) :: Error_descript	! error save
   integer, intent(out) :: INFO	! error description
   !------------------------------------------------------
   character(100) :: Folder_name, File_name
   integer count_lines, Reason, i_cur, ind, FN_skf, ToA, N_basis_siz
   logical file_exist, file_opened, read_well
   INFO = 0
   count_lines = 2
   
   read(FN,*,IOSTAT=Reason) TB_Hamil(i,j)%param_name    ! name of the directory with skf files
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
       write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
       INFO = 3
       goto 3426
   endif

   read(FN,*,IOSTAT=Reason) TB_Hamil(i,j)%rcut, TB_Hamil(i,j)%d  ! [A] cut off, and width of cut-off region [A]
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
       write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
       INFO = 3
       goto 3426
   endif

   Folder_name = trim(adjustl(m_INPUT_directory))//numpar%path_sep//trim(adjustl(m_DFTB_directory))//numpar%path_sep ! folder with all DFTB data
   Folder_name = trim(adjustl(Folder_name))//trim(adjustl(TB_Hamil(i,j)%param_name))    ! folder with chosen parameters sets
   
   ! Construct name of the skf file:
   call construct_skf_filename( trim(adjustl(matter%Atoms(i)%Name)), trim(adjustl(matter%Atoms(j)%Name)), File_name)    ! module "Dealing_with_DFTB"
   File_name = trim(adjustl(Folder_name))//numpar%path_sep//trim(adjustl(File_name))

   ! Check if such DFTB parameterization exists:
   inquire(file=trim(adjustl(File_name)),exist=file_exist)
   if (.not.file_exist) then
      Error_descript = 'File '//trim(adjustl(File_name))//' not found, the program terminates'
      INFO = 1
      goto 3426
   endif
   FN_skf=111
   open(UNIT=FN_skf, FILE = trim(adjustl(File_name)), status = 'old', action='read')
   inquire(file=trim(adjustl(File_name)),opened=file_opened)
   if (.not.file_opened) then
      Error_descript = 'File '//trim(adjustl(File_name))//' could not be opened, the program terminates'
      INFO = 2
      goto 3426
   endif
   
   ToA = same_or_different_atom_types(trim(adjustl(matter%Atoms(i)%Name)), trim(adjustl(matter%Atoms(j)%Name))) ! module "Dealing_with_DFTB"
   call read_skf_file(FN_skf, TB_Hamil(i,j), TB_Repuls(i,j), ToA, Error_descript)    ! module "Dealing_with_DFTB"
   if (LEN(trim(adjustl(Error_descript))) > 0) then
      INFO = 5
      goto 3426
   endif
   
   ! Check which basis set is used: 0=s, 1=sp3, 2=sp3d5:
   if ((i == matter%N_KAO) .and. (j == matter%N_KAO)) then  ! only when all parameters for all elements are read from files:
      call idnetify_basis_size(TB_Hamil, N_basis_siz)  ! module "Dealing_with_DFTB"'
      numpar%N_basis_size = max(numpar%N_basis_size,N_basis_siz)
   endif
   
3426 continue 
   ! Close files that have been read through:
   call close_file('close', FN=FN_skf) ! module "Dealing_with_files"
   call close_file('close', FN=FN) ! module "Dealing_with_files"
end subroutine read_DFTB_TB_Params



subroutine read_DFTB_TB_Params_no_rep(FN, i,j, TB_Hamil, TB_Repuls, numpar, matter, Error_descript, INFO)
   integer, intent(in) :: FN ! file number where to read from
   integer, intent(in) :: i, j  ! numbers of pair of elements for which we read the data
   type(TB_H_DFTB), dimension(:,:), intent(inout) ::  TB_Hamil ! parameters of the Hamiltonian of TB
   type(TB_Rep_DFTB_no), dimension(:,:), intent(inout) ::  TB_Repuls ! parameters of the Hamiltonian of TB
   type(Numerics_param), intent(inout) :: numpar 	! all numerical parameters
   type(Solid), intent(in) :: matter	! all material parameters
   character(*), intent(out) :: Error_descript	! error save
   integer, intent(out) :: INFO	! error description
   !------------------------------------------------------
   character(100) :: Folder_name, File_name, Inner_folder_name
   integer count_lines, Reason, i_cur, ind, FN_skf, ToA, N_basis_siz
   logical file_exist, file_opened, read_well
   INFO = 0
   count_lines = 2

   read(FN,*,IOSTAT=Reason) TB_Hamil(i,j)%param_name    ! name of the directory with skf files
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
       write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
       INFO = 3
       goto 3426
   endif

   ! folder with all DFTB data:
   Folder_name = trim(adjustl(m_INPUT_directory))//numpar%path_sep//trim(adjustl(m_DFTB_norep_directory))//numpar%path_sep
   Folder_name = trim(adjustl(Folder_name))//trim(adjustl(TB_Hamil(i,j)%param_name))

   ! folder with chosen parameters sets:
   select case (trim(adjustl(TB_Hamil(i,j)%param_name)))
   case default ! e.g. '1element'
      ! no inner folders, just skf-files
   case ('2elements')
      read(FN,*,IOSTAT=Reason) Inner_folder_name   ! read the inner folder name
      call read_file(Reason, count_lines, read_well)
      if (.not. read_well) then
         write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
         INFO = 3
         goto 3426
      endif
      Folder_name = trim(adjustl(Folder_name))//numpar%path_sep//trim(adjustl(Inner_folder_name))
      TB_Hamil(i,j)%param_name = trim(adjustl(TB_Hamil(i,j)%param_name))//numpar%path_sep//trim(adjustl(Inner_folder_name))
   endselect

   read(FN,*,IOSTAT=Reason) TB_Hamil(i,j)%rcut, TB_Hamil(i,j)%d  ! [A] cut off, and width of cut-off region [A]
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
       write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
       INFO = 3
       goto 3426
   endif

   ! Construct name of the skf file:
   call construct_skf_filename( trim(adjustl(matter%Atoms(i)%Name)), trim(adjustl(matter%Atoms(j)%Name)), File_name, '_no_repulsion')    ! module "Dealing_with_DFTB"

   File_name = trim(adjustl(Folder_name))//numpar%path_sep//trim(adjustl(File_name))

   ! Check if such DFTB parameterization exists:
   inquire(file=trim(adjustl(File_name)),exist=file_exist)
   if (.not.file_exist) then
      Error_descript = 'File '//trim(adjustl(File_name))//' not found, the program terminates'
      INFO = 1
      goto 3426
   endif
   FN_skf=111
   open(UNIT=FN_skf, FILE = trim(adjustl(File_name)), status = 'old', action='read')
   inquire(file=trim(adjustl(File_name)),opened=file_opened)
   if (.not.file_opened) then
      Error_descript = 'File '//trim(adjustl(File_name))//' could not be opened, the program terminates'
      INFO = 2
      goto 3426
   endif

   ToA = same_or_different_atom_types(trim(adjustl(matter%Atoms(i)%Name)), trim(adjustl(matter%Atoms(j)%Name))) ! module "Dealing_with_DFTB"
   call read_skf_file_no_rep(FN_skf, TB_Hamil(i,j), TB_Repuls(i,j), ToA, Error_descript)    ! module "Dealing_with_DFTB"
   if (LEN(trim(adjustl(Error_descript))) > 0) then
      INFO = 5
      goto 3426
   endif

   ! Check which basis set is used: 0=s, 1=sp3, 2=sp3d5:
   if ((i == matter%N_KAO) .and. (j == matter%N_KAO)) then  ! only when all parameters for all elements are read from files:
      call idnetify_basis_size(TB_Hamil, N_basis_siz)  ! module "Dealing_with_DFTB"'
      numpar%N_basis_size = max(numpar%N_basis_size,N_basis_siz)
   endif

3426 continue
   ! Close files that have been read through:
   call close_file('close', FN=FN_skf) ! module "Dealing_with_files"
   call close_file('close', FN=FN) ! module "Dealing_with_files"
end subroutine read_DFTB_TB_Params_no_rep



subroutine read_3TB_TB_Params(FN, i, j, TB_Hamil, numpar, matter, Error_descript, INFO)
   integer, intent(in) :: FN ! file number where to read from
   integer, intent(in) :: i, j  ! numbers of pair of elements for which we read the data
   type(TB_H_3TB), dimension(:,:), intent(inout) ::  TB_Hamil ! parameters of the Hamiltonian of TB
   type(Numerics_param), intent(inout) :: numpar 	! all numerical parameters
   type(Solid), intent(in) :: matter	! all material parameters
   character(*), intent(out) :: Error_descript	! error save
   integer, intent(out) :: INFO	! error description
   !------------------------------------------------------
   character(100) :: Folder_name, File_name
   character(200) :: Filename_onsite, Filename_2body, Filename_3body
   integer count_lines, Reason, FN_onsite, FN_2bdy, FN_3bdy, N_basis_siz
   logical file_exist, file_opened, read_well, file_exists

   ! To start with:
   INFO = 0
   count_lines = 1
   FN_onsite=110
   FN_2bdy=111
   FN_3bdy=112

   ! Read the second line of the input file:
   read(FN,*,IOSTAT=Reason) TB_Hamil(i,j)%rcut, TB_Hamil(i,j)%d  ! [A] cut off, and width of cut-off region [A]
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
       write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
       INFO = 3
       goto 3500
   endif

   read(FN,*,IOSTAT=Reason) TB_Hamil(i,j)%rc  ! distance rescaling coefficient
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
       write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
       INFO = 3
       goto 3500
   endif

   read(FN,*,IOSTAT=Reason) TB_Hamil(i,j)%include_3body  ! flag, include 3-body terms or not
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      TB_Hamil(i,j)%include_3body = .false.  ! by default, exclude 3-body terms
   endif

   read(FN,*,IOSTAT=Reason) TB_Hamil(i,j)%nullify_diag_cf  ! flag, exclude diagonal part of crystal field
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      TB_Hamil(i,j)%nullify_diag_cf = .true.  ! by default, exclude diagonal part of crystal field
   endif


   ! Folder with all 3TB data:
   Folder_name = trim(adjustl(m_INPUT_directory))//numpar%path_sep//trim(adjustl(m_3TB_directory))//numpar%path_sep

   ! Read onsite parameters:
   Filename_onsite = trim(adjustl(Folder_name))//trim(adjustl(m_3TB_onsite_data))
   inquire(file=trim(adjustl(Filename_onsite)),exist=file_exists)
   if (.not.file_exists) then
      INFO = 1 ! file with onsite parameters not found
      Error_descript = 'File '//trim(adjustl(Filename_onsite))//' not found, the program terminates'
      goto 3500
   endif
   open(UNIT=FN_onsite, FILE = trim(adjustl(Filename_onsite)), status = 'old', action='read')
   inquire(file=trim(adjustl(Filename_onsite)),opened=file_opened)
   if (.not.file_opened) then
      Error_descript = 'File '//trim(adjustl(Filename_onsite))//' could not be opened, the program terminates'
      INFO = 2
      goto 3500
   endif
   ! Having constructed the name of the file with onsite parameters, read it:
   call read_3TB_onsite_file(FN_onsite, trim(adjustl(matter%Atoms(i)%Name)), TB_Hamil(i,j), &
                              N_basis_siz, Error_descript)    ! module "Dealing_with_3TB"
   if (LEN(trim(adjustl(Error_descript))) > 0) then
      INFO = 5
      goto 3500
   endif

   ! Save the basis size as the maximal among all elements:
   numpar%N_basis_size = max(numpar%N_basis_size,N_basis_siz)



   ! Construct name of the 3TB files with 2-body and 3-body parameters:
   call construct_3TB_filenames(trim(adjustl(Folder_name)), trim(adjustl(matter%Atoms(i)%Name)), trim(adjustl(matter%Atoms(j)%Name)), &
                     numpar%path_sep, Filename_2body, Filename_3body, INFO)  ! module "Dealing_with_3TB"
   ! Check if such 3TB parameterization exists:
   if (INFO /= 0) then
      select case(INFO)
      case (1)
         Error_descript = 'File '//trim(adjustl(Filename_2body))//' not found, the program terminates'
         INFO = 1
      case (2)
         Error_descript = 'File '//trim(adjustl(Filename_3body))//' not found, the program terminates'
         INFO = 1
      case (3)
         Error_descript = 'File '//trim(adjustl(Filename_2body))//' not found, the program terminates'
         INFO = 1
      case (4)
         Error_descript = 'File '//trim(adjustl(Filename_3body))//' not found, the program terminates'
         INFO = 1
      end select
      goto 3500
   endif

   ! Open and read from the parameters files:
   ! 2-body parameters:
   open(UNIT=FN_2bdy, FILE = trim(adjustl(Filename_2body)), status = 'old', action='read')
   inquire(file=trim(adjustl(Filename_2body)),opened=file_opened)
   if (.not.file_opened) then
      Error_descript = 'File '//trim(adjustl(Filename_2body))//' could not be opened, the program terminates'
      INFO = 2
      goto 3500
   endif
   ! File exists and opened, read from it:
   call read_3TB_2bdy_file(FN_2bdy, trim(adjustl(matter%Atoms(i)%Name)), trim(adjustl(matter%Atoms(j)%Name)), &
                           TB_Hamil(i,j), Error_descript)    ! module "Dealing_with_3TB"
   if (LEN(trim(adjustl(Error_descript))) > 0) then
      INFO = 5
      goto 3500
   endif


   ! 3-body parameters:
   if (TB_Hamil(i,j)%include_3body) then  ! only if user defined it to include

      open(UNIT=FN_3bdy, FILE = trim(adjustl(Filename_3body)), status = 'old', action='read')
      inquire(file=trim(adjustl(Filename_3body)),opened=file_opened)
      if (.not.file_opened) then
         Error_descript = 'File '//trim(adjustl(Filename_3body))//' could not be opened, the program terminates'
         INFO = 2
         goto 3500
      endif
      ! File exists and opened, read from it:
      call read_3TB_3bdy_file(FN_3bdy, trim(adjustl(matter%Atoms(i)%Name)), trim(adjustl(matter%Atoms(j)%Name)), &
                           TB_Hamil(i,j), Error_descript)    ! module "Dealing_with_3TB"
      if (LEN(trim(adjustl(Error_descript))) > 0) then
         INFO = 5
         goto 3500
      endif
   endif ! (TB_Hamil(i,j)%include_3body)


3500 continue
   ! Close files that have been read through:
   call close_file('close', FN=FN_onsite) ! module "Dealing_with_files"
   call close_file('close', FN=FN_2bdy) ! module "Dealing_with_files"
   call close_file('close', FN=FN_3bdy) ! module "Dealing_with_files"
   call close_file('close', FN=FN) ! module "Dealing_with_files"


   ! While testing :
   if (INFO .NE. 0) then
      print*, trim(adjustl(Error_descript))
   endif
   !PAUSE 'pause read_3TB_TB_Params'

end subroutine read_3TB_TB_Params



subroutine read_BOP_TB_Params(FN, i,j, TB_Hamil, TB_Repuls, numpar, matter, Error_descript, INFO)
   integer, intent(in) :: FN ! file number where to read from
   integer, intent(in) :: i, j  ! numbers of pair of elements for which we read the data
   type(TB_H_BOP), dimension(:,:), intent(inout) ::  TB_Hamil ! parameters of the Hamiltonian of TB
   type(TB_Rep_BOP), dimension(:,:), intent(inout) ::  TB_Repuls    ! parameters of the repulsive potential
   type(Numerics_param), intent(inout) :: numpar 	! all numerical parameters
   type(Solid), intent(in) :: matter	! all material parameters
   character(*), intent(out) :: Error_descript	! error save
   integer, intent(out) :: INFO	! error description
   !------------------------------------------------------
   character(200) :: Folder_name, File_name
   real(8) :: bond_length   ! to construct repulsive part of BOP potential, we need to know dimer bond length [A]
   integer count_lines, Reason, FN_BOP, N_basis_siz
   logical :: file_exist, file_opened, read_well, file_exists, data_exists
   INFO = 0
   count_lines = 2
   
   read(FN,*,IOSTAT=Reason) TB_Hamil(i,j)%rcut, TB_Hamil(i,j)%dcut  ! [A] cut off, and width of cut-off region [A]
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
       write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
       INFO = 3
       goto 3427
   endif

   Folder_name = trim(adjustl(m_INPUT_directory))//numpar%path_sep//trim(adjustl(m_BOP_directory))//numpar%path_sep  ! folder with all BOP data
   File_name = trim(adjustl(Folder_name))//numpar%path_sep//trim(adjustl(m_BOP_file))   ! file with BOP parameters, module "Dealing_with_BOP"

   ! Check if such BOP parameterization exists:
   inquire(file=trim(adjustl(File_name)),exist=file_exist)

   if (.not.file_exist) then
      Error_descript = 'File '//trim(adjustl(File_name))//' not found, the program terminates'
      INFO = 1
      goto 3427
   endif
   FN_BOP=1111
   open(UNIT=FN_BOP, FILE = trim(adjustl(File_name)), status = 'old', action='read')
   inquire(file=trim(adjustl(File_name)),opened=file_opened)
   if (.not.file_opened) then
      Error_descript = 'File '//trim(adjustl(File_name))//' could not be opened, the program terminates'
      INFO = 2
      goto 3427
   endif

   if (j >= i) then ! reading lower triangle together wit the upper one:
      call read_BOP_parameters(FN_BOP, trim(adjustl(matter%Atoms(i)%Name)), trim(adjustl(matter%Atoms(j)%Name)), &
                                            TB_Hamil, i, j, Error_descript)    ! module "Dealing_with_BOP"
   endif

   if (LEN(trim(adjustl(Error_descript))) > 0) then
      INFO = 5
      goto 3427
   endif
   
   ! Check which basis set is used: 0=s, 1=sp3, 2=sp3d5:
   if (i == j) then
      call idnetify_basis_size_BOP(TB_Hamil(i,j), N_basis_siz)  ! module "Dealing_with_BOP"'
      numpar%N_basis_size = max(numpar%N_basis_size, N_basis_siz)
   endif

   ! Now, deal with the repulsive part of BOP:
   if (j >= i) then ! reading lower triangle together wit the upper one:
      ! Make sure either file with repulsive potential exists, or we can create it:
      call check_if_repulsion_exists(INT(matter%Atoms(i)%Z), trim(adjustl(matter%Atoms(i)%Name)), &
                INT(matter%Atoms(j)%Z), trim(adjustl(matter%Atoms(j)%Name)), &
                Folder_name, numpar%path_sep, file_exists, data_exists, bond_length, Error_descript) ! module "Dealing_with_BOP"
      if (LEN(trim(adjustl(Error_descript))) > 0) then
         INFO = 4
         goto 3427
      endif

      ! If we have file with repulsive potential, read it from it:
      if (file_exists) then ! read from it:
         call read_BOP_repulsive(TB_Repuls, i, j, Folder_name, numpar%path_sep, &
            trim(adjustl(matter%Atoms(i)%Name)), trim(adjustl(matter%Atoms(j)%Name)), Error_descript) ! module "Dealing_with_BOP"

      elseif (data_exists) then ! construct new repulsive potential:
         numpar%BOP_bond_length = bond_length   ! [A] save to reuse later
         numpar%create_BOP_repulse = .true. ! marker to construct BOP repulsive potential
         numpar%BOP_Folder_name = Folder_name   ! directory where to find it

      else ! no way to access repulsive part
         INFO = 5
         goto 3427
      endif
   endif
   
3427 continue 
   ! Close files that have been read through:
   call close_file('close', FN=FN_BOP) ! module "Dealing_with_files"
   call close_file('close', FN=FN) ! module "Dealing_with_files"
end subroutine read_BOP_TB_Params




subroutine read_xTB_Params(FN, i,j, TB_Hamil, TB_Repuls, numpar, matter, Error_descript, INFO)
   integer, intent(in) :: FN ! file number where to read from
   integer, intent(in) :: i, j  ! numbers of pair of elements for which we read the data
   type(TB_H_xTB), dimension(:,:), intent(inout) ::  TB_Hamil ! parameters of the Hamiltonian of TB
   type(TB_Rep_xTB), dimension(:,:), intent(inout) ::  TB_Repuls ! parameters of the Hamiltonian of TB
   type(Numerics_param), intent(inout) :: numpar 	! all numerical parameters
   type(Solid), intent(in) :: matter	! all material parameters
   character(*), intent(out) :: Error_descript	! error save
   integer, intent(out) :: INFO	! error description
   !------------------------------------------------------
   character(100) :: Folder_name, File_name
   integer count_lines, Reason, i_cur, ind, FN_skf, ToA, N_basis_siz
   logical file_exist, file_opened, read_well
   INFO = 0 ! to start with no error
   count_lines = 2

   ! name of the xTB parameterization (currently, only GFN0 is supported!); number of GTO primitives
   read(FN,*,IOSTAT=Reason) TB_Hamil(i,j)%param_name, TB_Hamil(i,j)%Nprim
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
       write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
       INFO = 3
       goto 3428
   endif

   read(FN,*,IOSTAT=Reason) TB_Hamil(i,j)%rcut, TB_Hamil(i,j)%d  ! [A] cut off, and width of cut-off region [A]
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
       write(Error_descript,'(a,i3)') 'Could not read line ', count_lines
       INFO = 3
       goto 3428
   endif

   Folder_name = trim(adjustl(m_INPUT_directory))//numpar%path_sep//trim(adjustl(m_xTB_directory))//numpar%path_sep ! folder with xTB data

   ! Read xTB parameters:
   call read_xTB_parameters(Folder_name, i, j, TB_Hamil, TB_Repuls, numpar, matter, Error_descript, INFO)    ! module "Dealing_with_xTB"

   ! Check which basis set is used: 0=s; 1=ss*; 2=sp3; 3=sp3s*; 4=sp3d5; 5=sp3d5s*
   if ((i == matter%N_KAO) .and. (j == matter%N_KAO)) then  ! only when all parameters for all elements are read from files:
      call identify_basis_size_xTB(TB_Hamil, N_basis_siz)  ! module "Dealing_with_DFTB"'
      ! Save the index of the basis set:
      numpar%N_basis_size = max(numpar%N_basis_size,N_basis_siz)

      ! Identify the parameters of the AO:
      call identify_AOs_xTB(TB_Hamil)   ! module "Dealing_with_xTB"


   endif

3428 continue
   ! Close files that have been read through:
   call close_file('close', FN=FN) ! module "Dealing_with_files"
end subroutine read_xTB_Params



subroutine read_numerical_parameters(File_name, matter, numpar, laser, Scell, user_data, Err)
   character(*), intent(in) :: File_name
   type(Solid), intent(inout) :: matter	! all material parameters
   type(Numerics_param), intent(inout) :: numpar 	! all numerical parameters
   type(Pulse), dimension(:), allocatable, intent(inout) :: laser	! Laser pulse parameters
   type(Super_cell), dimension(:), intent(inout) :: Scell  ! supercell with all the atoms as one object
   type(User_overwrite_data), intent(inout) :: user_data   ! atomic data provided by the user
   type(Error_handling), intent(inout) :: Err	! error save
   !---------------------------------
   integer FN, N, Reason, count_lines, i, NSC, temp1, temp2, temp3
   logical file_opened, read_well
   character(100) Error_descript, temp_ch

   NSC = 1 ! for now, we only have 1 supercell...

   !open(NEWUNIT=FN, FILE = trim(adjustl(File_name)), status = 'old')
   FN=108
   open(UNIT=FN, FILE = trim(adjustl(File_name)), status = 'old', action='read')
   inquire(file=trim(adjustl(File_name)),opened=file_opened)
   if (.not.file_opened) then
      Error_descript = 'File '//trim(adjustl(File_name))//' could not be opened, the program terminates'
      call Save_error_details(Err, 2, Error_descript)
      print*, trim(adjustl(Error_descript))
      goto 3418
   endif

   ! number of unit-cells in X,Y,Z:
   read(FN,*,IOSTAT=Reason) matter%cell_x, matter%cell_y, matter%cell_z 
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i5,a,$)') 'Could not read line ', count_lines, ' in file '//trim(adjustl(File_name))
      call Save_error_details(Err, 3, Error_descript)
      print*, trim(adjustl(Error_descript))
      goto 3418
   endif
   
   ! periodicity along X,Y,Z directions:
   read(FN,*,IOSTAT=Reason) temp1, temp2, temp3
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i5,a,$)') 'Could not read line ', count_lines, ' in file '//trim(adjustl(File_name))
      call Save_error_details(Err, 3, Error_descript)
      print*, trim(adjustl(Error_descript))
      goto 3418
   endif
   numpar%r_periodic(:) = .true.	! periodic by default
   if (temp1 == 0) numpar%r_periodic(1) = .false.	! along X
   if (temp2 == 0) numpar%r_periodic(2) = .false.	! along Y   
   if (temp3 == 0) numpar%r_periodic(3) = .false.	! along Z

   ! where to take atomic data from (EADL, CDF, XATOM...):
   read(FN,*,IOSTAT=Reason) numpar%At_base
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i5,a,$)') 'Could not read line ', count_lines, ' in file '//trim(adjustl(File_name))
      call Save_error_details(Err, 3, Error_descript)
      print*, trim(adjustl(Error_descript))
      goto 3418
   endif

   ! [g/cm^3] density of the material (used in MC in case of EADL parameters):
   read(FN,*,IOSTAT=Reason) matter%dens
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i5,a,$)') 'Could not read line ', count_lines, ' in file '//trim(adjustl(File_name))
      call Save_error_details(Err, 3, Error_descript)
      print*, trim(adjustl(Error_descript))
      goto 3418
   endif

   ! number of iterations in the MC module:
   read(FN,*,IOSTAT=Reason) numpar%NMC
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i5,a,$)') 'Could not read line ', count_lines, ' in file '//trim(adjustl(File_name))
      call Save_error_details(Err, 3, Error_descript)
      print*, trim(adjustl(Error_descript))
      goto 3418
   endif

   ! number of threads for OPENMP:
   read(FN,*,IOSTAT=Reason) numpar%NOMP
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i5,a,$)') 'Could not read line ', count_lines, ' in file '//trim(adjustl(File_name))
      call Save_error_details(Err, 3, Error_descript)
      print*, trim(adjustl(Error_descript))
      goto 3418
   endif
   
   ! MD algorithm (0=Verlet, 2d order; 1=Yoshida, 4th order)
   read(FN,*,IOSTAT=Reason) numpar%MD_algo
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i5,a,$)') 'Could not read line ', count_lines, ' in file '//trim(adjustl(File_name))
      call Save_error_details(Err, 3, Error_descript)
      print*, trim(adjustl(Error_descript))
      goto 3418
   endif

   ! Include (1) or exclude (0) atopmic motion:
   read(FN,*,IOSTAT=Reason) N
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i5,a,$)') 'Could not read line ', count_lines, ' in file '//trim(adjustl(File_name))
      call Save_error_details(Err, 3, Error_descript)
      print*, trim(adjustl(Error_descript))
      goto 3418
   endif
   if (N .EQ. 1) then
      numpar%do_atoms = .true.	! Atoms move
   else
      numpar%do_atoms = .false.	! Frozen atoms
   endif

   ! Parinello-Rahman super-vell mass coefficient
   read(FN,*,IOSTAT=Reason) matter%W_PR
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i5,a,$)') 'Could not read line ', count_lines, ' in file '//trim(adjustl(File_name))
      call Save_error_details(Err, 3, Error_descript)
      print*, trim(adjustl(Error_descript))
      goto 3418
   endif


   ! Time step for MD [fs]:
   read(FN,*,IOSTAT=Reason) numpar%MD_step_grid_file ! file with time grid, or timestep for md [fs]
   call read_file(Reason, count_lines, read_well)
   ! If read well, interpret it and set timestep or time-grid:
   call set_MD_step_grid(numpar%MD_step_grid_file, numpar, read_well, Error_descript)    ! below
   if (.not. read_well) then
      write(Error_descript,'(a,i5,a,$)') 'Could not read line ', count_lines, ' in file '//trim(adjustl(File_name))
      call Save_error_details(Err, 3, Error_descript)
      print*, trim(adjustl(Error_descript))
      goto 3418
   endif


   ! save data into files every 'dt_save_time' [fs]
   read(FN,*,IOSTAT=Reason) numpar%dt_save  ! save data into files every 'dt_save_time' [fs]
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i5,a,$)') 'Could not read line ', count_lines, ' in file '//trim(adjustl(File_name))
      call Save_error_details(Err, 3, Error_descript)
      print*, trim(adjustl(Error_descript))
      goto 3418
   endif

   ! it's = 1 if P=const, or = 0 if V=const:
   read(FN,*,IOSTAT=Reason) N	! It's = 0 if P=const, or = 1 if V=const
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i5,a,$)') 'Could not read line ', count_lines, ' in file '//trim(adjustl(File_name))
      call Save_error_details(Err, 3, Error_descript)
      print*, trim(adjustl(Error_descript))
      goto 3418
   endif
   if (N .EQ. 1) then
      numpar%p_const = .true.	! P=const
   else
      numpar%p_const = .false.	! V=const
   endif

   ! external pressure [Pa] (0 = normal atmospheric pressure):
   read(FN,*,IOSTAT=Reason) matter%p_ext  ! External pressure [Pa] (0 = normal atmospheric pressure)
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i5,a,$)') 'Could not read line ', count_lines, ' in file '//trim(adjustl(File_name))
      call Save_error_details(Err, 3, Error_descript)
      print*, trim(adjustl(Error_descript))
      goto 3418
   endif
!    if (matter%p_ext < 0.0d0) matter%p_ext = g_P_atm	! atmospheric pressure

   ! SCC:
   read(FN,*,IOSTAT=Reason) numpar%scc, numpar%scc_gam_ind, numpar%scc_mix
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i5,a,$)') 'Could not read line ', count_lines, ' in file '//trim(adjustl(File_name))
      call Save_error_details(Err, 3, Error_descript)
      print*, trim(adjustl(Error_descript))
      goto 3418
   endif


   ! 3 numbers:
   ! scheme (0=decoupled electrons; 1=enforced energy conservation; 2=T=const; 3=BO; 4=relaxation time);
   ! when to start coupling [fs];
   ! Characteristic relaxation time [fs];
   read(FN,*,IOSTAT=Reason) numpar%el_ion_scheme, numpar%t_Te_Ee, numpar%tau_fe
   call read_file(Reason, count_lines, read_well)
   if (Reason /= 0) then   ! probably only two number are given (legacy format)
      numpar%tau_fe = 1.0d0   ! [fs]
      print*, 'Relaxation time is not provided, assuming default value:', numpar%tau_fe, '[fs]'
      ! Trying to read the first 2 numbers from the same line:
      backspace(FN)  ! back one line
      count_lines = count_lines - 1 ! renumber it to continue from the same line
      read(FN,*,IOSTAT=Reason) numpar%el_ion_scheme, numpar%t_Te_Ee  ! try reading it again
      call read_file(Reason, count_lines, read_well)
      if (.not. read_well) then
         write(Error_descript,'(a,i5,a,$)') 'Could not read line ', count_lines, ' in file '//trim(adjustl(File_name))
         call Save_error_details(Err, 3, Error_descript)
         print*, trim(adjustl(Error_descript))
         goto 3418
      endif
   endif


   ! 0=no coupling, 1=dynamical coupling (2=Fermi-golden_rule)
   read(FN,*,IOSTAT=Reason) numpar%NA_kind
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i5,a,$)') 'Could not read line ', count_lines, ' in file '//trim(adjustl(File_name))
      call Save_error_details(Err, 3, Error_descript)
      print*, trim(adjustl(Error_descript))
      goto 3418
   endif
   if (numpar%NA_kind .EQ. 0) then
      numpar%Nonadiabat = .false. ! excluded
   else
      numpar%Nonadiabat = .true.  ! included
   endif

   ! [fs] when to switch on the nonadiabatic coupling:
   read(FN,*,IOSTAT=Reason) numpar%t_NA, numpar%M2_scaling ! [fs] start of the nonadiabatic coupling; scaling factor
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i5,a,$)') 'Could not read line ', count_lines, ' in file '//trim(adjustl(File_name))
      call Save_error_details(Err, 3, Error_descript)
      print*, trim(adjustl(Error_descript))
      goto 3418
   endif

   ! [eV] acceptance window and quasidegeneracy window for nonadiabatic coupling:
   read(FN,*,IOSTAT=Reason) numpar%acc_window, numpar%degeneracy_eV
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i5,a,$)') 'Could not read line ', count_lines, ' in file '//trim(adjustl(File_name))
      call Save_error_details(Err, 3, Error_descript)
      print*, trim(adjustl(Error_descript))
      goto 3418
   endif

   ! calculate electornic heat conductivity (0=no, 1=yes): -- DOES NOT WORK, EXCLUDED UNTIL SOLVED
!    read(FN,*,IOSTAT=Reason) N
!    call read_file(Reason, count_lines, read_well)
!    if (.not. read_well) then
!       write(Error_descript,'(a,i5,a,$)') 'Could not read line ', count_lines, ' in file '//trim(adjustl(File_name))
!       call Save_error_details(Err, 3, Error_descript)
!       print*, trim(adjustl(Error_descript))
!       goto 3418
!    endif
!    if (N .EQ. 1) then
!       numpar%do_kappa = .true.	! included
!    else
!       numpar%do_kappa = .false.	! excluded
!    endif

   ! atoms quenching (0=no, 1=yes); starting from when [fs]; how often [fs]:
   read(FN,*,IOSTAT=Reason) N, numpar%at_cool_start, numpar%at_cool_dt ! include atomic cooling? When to start? How often?
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i5,a,$)') 'Could not read line ', count_lines, ' in file '//trim(adjustl(File_name))
      call Save_error_details(Err, 3, Error_descript)
      print*, trim(adjustl(Error_descript))
      goto 3418
   endif
   if (N .EQ. 1) then
      numpar%do_cool = .true.	! included
   else
      numpar%do_cool = .false.	! excluded
   endif

   ! 0=no heat transport, 1=include heat transport; thermostat temperature for ATOMS [K]:
   read(FN,*,IOSTAT=Reason) N, matter%T_bath, matter%tau_bath
   call read_file(Reason, count_lines, read_well)
   if (read_well) then
      if (N .EQ. 1) then
         numpar%Transport = .true.	 ! included
      else
         numpar%Transport = .false. ! excluded
      endif
      matter%T_bath = matter%T_bath/g_kb	! [eV] thermostat temperature for atoms
   else ! maybe there is a filename given to read from instead of numbers:
      backspace(FN)  ! go back and try to read the line again
      read(FN,*,IOSTAT=Reason) numpar%At_bath_step_grid_file  ! name of file with parameters
      call read_file(Reason, count_lines, read_well)
      !print*, numpar%At_bath_step_grid_file, Reason
      if (.not. read_well) then
         write(Error_descript,'(a,i5,a,$)') 'Could not read line ', count_lines, ' in file '//trim(adjustl(File_name))
         call Save_error_details(Err, 3, Error_descript)
         print*, trim(adjustl(Error_descript))
         goto 3418
      endif
      ! If read well, try to interpret it and set parameters on time-grid:
      call set_Bath_grid_atoms(numpar, read_well, Error_descript)    ! below
      if (.not. read_well) then
         write(Error_descript,'(a,i5,a,$)') 'Could not read line ', count_lines, ' in file '//trim(adjustl(File_name))
         call Save_error_details(Err, 3, Error_descript)
         print*, trim(adjustl(Error_descript))
         goto 3418
      endif
   endif

   ! 0=no heat transport, 1=include heat transport; thermostat temperature for ELECTRONS [K]:
   read(FN,*,IOSTAT=Reason) N, matter%T_bath_e, matter%tau_bath_e
   call read_file(Reason, count_lines, read_well)
   if (read_well) then
      if (N .EQ. 1) then
         numpar%Transport_e = .true.	 ! included
      else
         numpar%Transport_e = .false. ! excluded
      endif
      matter%T_bath_e = matter%T_bath_e/g_kb	! [eV] thermostat temperature for electrons
   else
      ! maybe there is a filename given to read from instead of numbers:
      backspace(FN)  ! go back and try to read the line again
      read(FN,*,IOSTAT=Reason) numpar%El_bath_step_grid_file  ! name of file with parameters
      call read_file(Reason, count_lines, read_well)
      if (.not. read_well) then
         write(Error_descript,'(a,i5,a,$)') 'Could not read line ', count_lines, ' in file '//trim(adjustl(File_name))
         call Save_error_details(Err, 3, Error_descript)
         print*, trim(adjustl(Error_descript))
         goto 3418
      endif
      ! If read well, try to interpret it and set parameters on time-grid:
      call set_Bath_grid_electrons(numpar, read_well, Error_descript)    ! below
      if (.not. read_well) then
         write(Error_descript,'(a,i5,a,$)') 'Could not read line ', count_lines, ' in file '//trim(adjustl(File_name))
         call Save_error_details(Err, 3, Error_descript)
         print*, trim(adjustl(Error_descript))
         goto 3418
      endif
   endif


   ! [eV] cut-off energy, separating low-energy-electrons from high-energy-electrons:
   read(FN,*,IOSTAT=Reason) numpar%E_cut  ! [eV] cut-off energy for high-energy-electrons
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i5,a,$)') 'Could not read line ', count_lines, ' in file '//trim(adjustl(File_name))
      call Save_error_details(Err, 3, Error_descript)
      print*, trim(adjustl(Error_descript))
      goto 3418
   endif
   if (numpar%E_cut <= 0.0d0) then ! use dynamical evolution of E_cut adjusting it to top-most CB level
      numpar%E_cut_dynamic = .true.  ! change E_cut
   else
      numpar%E_cut_dynamic = .false. ! do not change E_cut
   endif

   ! [eV] work function, for electron emission:
   read(FN,*,IOSTAT=Reason) numpar%E_work  ! [eV] work function for electron emission
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i5,a,$)') 'Could not read line ', count_lines, ' in file '//trim(adjustl(File_name))
      call Save_error_details(Err, 3, Error_descript)
      print*, trim(adjustl(Error_descript))
      goto 3418
   endif
   if (numpar%E_work <= 0.0d0) then ! it is a condition on the counter of collisions:
      ! don't forget to exclude electrons that made more collisions than allowed
   else if (numpar%E_work <= numpar%E_cut) then ! exclude it from the calculations:
      numpar%E_work = 1.0d30
   endif
   
   ! save electron energy levels (1) or not (0):
   read(FN,*,IOSTAT=Reason) N  ! save electron energy levels (1) or not (0)
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i5,a,$)') 'Could not read line ', count_lines, ' in file '//trim(adjustl(File_name))
      call Save_error_details(Err, 3, Error_descript)
      print*, trim(adjustl(Error_descript))
      goto 3418
   endif
   if (N .EQ. 1) then
      numpar%save_Ei = .true.	! included
   else
      numpar%save_Ei = .false.	! excluded
   endif
   
   ! save DOS (1=Gamma; 2=k-points) or not (0):
   read(FN,*,IOSTAT=Reason) N, numpar%Smear_DOS, numpar%DOS_splitting ! save DOS (1) or not (0), smearing width, do partial DOS or no
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i5,a,$)') 'Could not read line ', count_lines, ' in file '//trim(adjustl(File_name))
      call Save_error_details(Err, 3, Error_descript)
      print*, trim(adjustl(Error_descript))
      goto 3418
   endif
   if (abs(N) == 2) then
      ! if the user wanted complex k-points, leave it be, otherwise, overwrite it with the option of complex k for DOS
      ! * Note that it SWITCHES OFF the probe-pulse calculations in this case
      ! which means it is currently not possible to get gamma-point probe pulse, and multiple-k-points for DOS.
      ! They are connected: either both are calculated for multiple (and the same) k-points,
      ! or DOS calculation takes precedence, and probe is switched off:
      if (numpar%optic_model /= 2) then
         numpar%optic_model = -2    ! complex, for given number of k-points for DOS calculations
      endif
      numpar%save_DOS = .true.   ! included
   elseif (N == 1) then ! calculate with the same model used for the probe pulse (gamma-point or multiple k-points)
      numpar%save_DOS = .true.   ! included
   else ! no DOS output requested
      numpar%save_DOS = .false.  ! excluded
   endif
!    print*, 'DOS_in:', numpar%save_DOS, numpar%optic_model
   
   ! save Mulliken or not, and within which model: (0) no; (1) for atom types; 
   read(FN,*,IOSTAT=Reason) numpar%Mulliken_model
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i5,a,$)') 'Could not read line ', count_lines, ' in file '//trim(adjustl(File_name))
      call Save_error_details(Err, 3, Error_descript)
      print*, trim(adjustl(Error_descript))
      goto 3418
   endif

   ! save electron electron distribution (1) or not (0):
   !read(FN,*,IOSTAT=Reason) N  ! save electron distribution function (1) or not (0)
   read(FN,'(a)',IOSTAT=Reason) temp_ch   ! read parameters to interpret them in a subroutine
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i5,a,$)') 'Could not read line ', count_lines, ' in file '//trim(adjustl(File_name))
      call Save_error_details(Err, 3, Error_descript)
      print*, trim(adjustl(Error_descript))
      goto 3418
   endif
   call interprete_distribution_input(temp_ch, numpar, Scell(1), read_well) ! below
   if (.not. read_well) then
      write(Error_descript,'(a,i5,a,$)') 'Could not interprete line ', count_lines, ' in file '//trim(adjustl(File_name))
      call Save_error_details(Err, 3, Error_descript)
      print*, trim(adjustl(Error_descript))
      goto 3418
   endif

   ! save atomic pair correlation function (1) or not (0):
   read(FN,*,IOSTAT=Reason) N  ! save atomic pair correlation function (1) or not (0)
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i5,a,$)') 'Could not read line ', count_lines, ' in file '//trim(adjustl(File_name))
      call Save_error_details(Err, 3, Error_descript)
      print*, trim(adjustl(Error_descript))
      goto 3418
   endif
   if (N .EQ. 1) then
      numpar%save_PCF = .true.	! included
   else
      numpar%save_PCF = .false.	! excluded
   endif

   ! save atomic positions in XYZ (1) or not (0):
   read(FN,*,IOSTAT=Reason) N  ! save atomic positions in XYZ (1) or not (0)
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i5,a,$)') 'Could not read line ', count_lines, ' in file '//trim(adjustl(File_name))
      call Save_error_details(Err, 3, Error_descript)
      print*, trim(adjustl(Error_descript))
      goto 3418
   endif
   if (N .EQ. 1) then
      numpar%save_XYZ = .true.	! included
   else
      numpar%save_XYZ = .false.	! excluded
   endif
   
   ! save atomic positions in CIF (1) or not (0):
   read(FN,*,IOSTAT=Reason) N  ! save atomic positions in CIF (1) or not (0)
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i5,a,$)') 'Could not read line ', count_lines, ' in file '//trim(adjustl(File_name))
      call Save_error_details(Err, 3, Error_descript)
      print*, trim(adjustl(Error_descript))
      goto 3418
   endif
   if (N .EQ. 1) then
      numpar%save_CIF = .true.	! included printout atomic coordinates in CIF format
   else
      numpar%save_CIF = .false.	! excluded printout atomic coordinates in CIF format
   endif
   
   ! save raw data for atomic positions and velocities (1) or not (0):
   read(FN,*,IOSTAT=Reason) N
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i5,a,$)') 'Could not read line ', count_lines, ' in file '//trim(adjustl(File_name))
      call Save_error_details(Err, 3, Error_descript)
      print*, trim(adjustl(Error_descript))
      goto 3418
   endif
   if (N .EQ. 1) then
      numpar%save_raw = .true.	! included printout raw data
   else
      numpar%save_raw = .false.	! excluded printout raw data
   endif
   
   ! read power of mean displacement to print out (set integer N: <u^N>-<u0^N>):
   read(FN,*,IOSTAT=Reason) numpar%MSD_power
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i5,a,$)') 'Could not read line ', count_lines, ' in file '//trim(adjustl(File_name))
      call Save_error_details(Err, 3, Error_descript)
      print*, trim(adjustl(Error_descript))
      goto 3418
   endif
   
   ! save number of nearest neighbors within the digen radius (>0) or not (<=0):
   read(FN,*,IOSTAT=Reason) numpar%NN_radius
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i5,a,$)') 'Could not read line ', count_lines, ' in file '//trim(adjustl(File_name))
      call Save_error_details(Err, 3, Error_descript)
      print*, trim(adjustl(Error_descript))
      goto 3418
   endif
   if (numpar%NN_radius > 1.0e-2) then
      numpar%save_NN = .true.	! included printout nearest neighbors
   else
      numpar%save_NN = .false.	! excluded printout nearest neighbors
   endif

   !  which format to use to plot figures: eps, jpeg, gif, png, pdf
   read(FN,*,IOSTAT=Reason) numpar%fig_extention
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i5,a,$)') 'Could not read line ', count_lines, ' in file '//trim(adjustl(File_name))
      call Save_error_details(Err, 3, Error_descript)
      print*, trim(adjustl(Error_descript))
      goto 3418
   endif
   select case ( trim(adjustl(numpar%fig_extention)) )
   case ('JPEG', 'JPEg', 'JPeg', 'Jpeg', 'jpeg', 'JPG', 'jpg')
      numpar%fig_extention = 'jpeg'
      numpar%ind_fig_extention = 2
   case ('GIF', 'GIf', 'Gif', 'gif')
      numpar%fig_extention = 'gif'
      numpar%ind_fig_extention = 3
   case ('PNG', 'PNg', 'Png', 'png')
      numpar%fig_extention = 'png'
      numpar%ind_fig_extention = 4
   case ('PDF', 'PDf', 'Pdf', 'pdf')
      numpar%fig_extention = 'pdf'
      numpar%ind_fig_extention = 5
   case default ! eps
      numpar%fig_extention = 'eps'
      numpar%ind_fig_extention = 1
   end select
   
   ! number of k-points in each direction (used only for Trani-k!):
   read(FN,*,IOSTAT=Reason) numpar%ixm, numpar%iym, numpar%izm
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i5,a,$)') 'Could not read line ', count_lines, ' in file '//trim(adjustl(File_name))
      call Save_error_details(Err, 3, Error_descript)
      print*, trim(adjustl(Error_descript))
      goto 3418
   endif

   !----------------------------------------
   ! Read optional data provided by the user (e.g., to overwrite default atomic data):
   call read_user_additional_data(FN, count_lines, matter, Scell, NSC, user_data)   ! below


   ! Close this file, it has been read through:
3418 if (file_opened) close(FN)
end subroutine read_numerical_parameters



subroutine interprete_distribution_input(temp_ch, numpar, Scell, read_well)
   character(*), intent(in) :: temp_ch ! line read from the input file
   type(Numerics_param), intent(inout) :: numpar ! all numerical parameters
   type(Super_cell), intent(inout) :: Scell  ! supercell with all the atoms as one object
   logical, intent(inout) :: read_well
   !--------------------
   integer :: count_lines, Reason, N, Nsiz, i
   real(8) :: dE, Emax, Emin, dE_min

   count_lines = 0
   read_well = .true.   ! to start with
   ! Default values:
   numpar%save_fe = .false.
   numpar%save_fe_grid = .false.
   dE_min = 1.0d-4   ! [eV] minimal allowed grid step
   dE = 0.1d0  ! [eV] energy grid step
   Emin = -30.0d0 ! [eV] energy grid start
   Emax = 100.0d0 ! [eV] energy grid end

   read(temp_ch,*,IOSTAT=Reason) N, dE, Emax
   call read_file(Reason, count_lines, read_well)    ! module "Dealing_with_files"
   if (.not. read_well) then ! something wrong with the user-defined grid
      ! try reading just the first flag, no grid parameters
      read(temp_ch,*,IOSTAT=Reason) N
      call read_file(Reason, count_lines, read_well)    ! module "Dealing_with_files"
      if (.not. read_well) then ! something wrong with the user-defined grid
         print*, 'Trouble reading the line with electronic distribution parameters, fe will not be printed out!'
         N = 0 ! by default, no printing out
      endif
   else
      if ((dE < dE_min) .and. (abs(N) == 2)) then
         dE = dE_min
         print*, 'Energy grid step for fe is too small, using the default value:', dE_min
      endif
   endif

   select case (N)
   case (1) ! printout distribution on TB energy levels
      numpar%save_fe = .true.
   case (2) ! printout distribution on TB energy levels and on the user-defined grid
      numpar%save_fe = .true.
      numpar%save_fe_grid = .true.
   case (-2) ! printout distribution on the user-defined grid, but not on TB energy levels
      numpar%save_fe_grid = .true.
   end select

   if (numpar%save_fe_grid) then
      ! Now we know the grid parameters:
      Nsiz = INT((Emax-Emin)/dE)
      ! Set the default grids:
      allocate(Scell%E_fe_grid(Nsiz), source=0.0d0)
      allocate(Scell%fe_on_grid(Nsiz), source=0.0d0)
      allocate(Scell%fe_high_on_grid(Nsiz), source=0.0d0)
      allocate(numpar%high_DOS(Nsiz), source=0.0d0)
      allocate(Scell%fe_norm_on_grid(Nsiz), source=0.0d0)
      allocate(Scell%fe_norm_high_on_grid(Nsiz), source=0.0d0)
      ! Create the grid:
      Scell%E_fe_grid(1) = Emin
      do i = 2, Nsiz
         Scell%E_fe_grid(i) = Scell%E_fe_grid(i-1) + dE
      enddo
   endif
end subroutine interprete_distribution_input



subroutine set_Bath_grid_electrons(numpar, read_well_out, Error_descript)
   type(Numerics_param), intent(inout) :: numpar ! all numerical parameters
   logical, intent(inout) :: read_well_out
   character(*), intent(inout) :: Error_descript
   !-----------------------------------------
   character(200) :: Path, full_file_name
   logical :: file_exist, read_well
   integer :: FN, Nsiz, count_lines, Reason, i

   read_well_out = .false.   ! to start with
   numpar%Transport_e = .false. ! to start with

   Path = trim(adjustl(m_INPUT_directory))//numpar%path_sep    ! where to find the file with the data
   full_file_name = trim(adjustl(Path))//trim(adjustl(numpar%El_bath_step_grid_file))   ! to read the file from the INPUT_DATA directory
   inquire(file=trim(adjustl(full_file_name)),exist=file_exist) ! check if input file is there
   if (file_exist) then ! try to read it, if there is a grid provided
      open(newunit = FN, FILE = trim(adjustl(full_file_name)), status = 'old', action='read')
      ! Find the grid size from the file:
      call Count_lines_in_file(FN, Nsiz) ! module "Dealing_with_files"
      ! Knowing the size, create the grid-array and read from the file:
      if (allocated(numpar%El_bath_reset_grid)) deallocate(numpar%El_bath_reset_grid) ! make sure it's possible to allocate
      allocate(numpar%El_bath_reset_grid(Nsiz)) ! allocate it
      if (allocated(numpar%El_bath_grid_Ta)) deallocate(numpar%El_bath_grid_Ta) ! make sure it's possible to allocate
      allocate(numpar%El_bath_grid_Ta(Nsiz)) ! allocate it
      if (allocated(numpar%El_bath_grid_tau)) deallocate(numpar%El_bath_grid_tau) ! make sure it's possible to allocate
      allocate(numpar%El_bath_grid_tau(Nsiz)) ! allocate it

      ! Read data on the grid from the file:
      count_lines = 0   ! just to start counting lines in the file
      do i = 1, Nsiz    ! read grid line by line from the file
         read(FN,*,IOSTAT=Reason) numpar%El_bath_reset_grid(i), numpar%El_bath_grid_Ta(i), numpar%El_bath_grid_tau(i)
         call read_file(Reason, count_lines, read_well)    ! module "Dealing_with_files"
         if (.not. read_well) then ! something wrong with the user-defined grid
            write(Error_descript,'(a,i3)') 'In the file '//trim(adjustl(numpar%El_bath_step_grid_file))//' could not read line ', count_lines
            goto 9997  ! couldn't read the data, exit the cycle
         endif
      enddo
      numpar%i_El_bath_dt = 1 ! to start from
      read_well_out = .true.     ! we read the grid from the file well

9997 call close_file('close', FN=FN) ! module "Dealing_with_files"
   endif ! file_exist
end subroutine set_Bath_grid_electrons


subroutine set_Bath_grid_atoms(numpar, read_well_out, Error_descript)
   type(Numerics_param), intent(inout) :: numpar 	! all numerical parameters
   logical, intent(inout) :: read_well_out
   character(*), intent(inout) :: Error_descript
   !-----------------------------------------
   character(200) :: Path, full_file_name
   logical :: file_exist, read_well
   integer :: FN, Nsiz, count_lines, Reason, i

   read_well_out = .false.   ! to start with
   numpar%Transport = .false. ! to start with

   Path = trim(adjustl(m_INPUT_directory))//numpar%path_sep    ! where to find the file with the data
   full_file_name = trim(adjustl(Path))//trim(adjustl(numpar%At_bath_step_grid_file))   ! to read the file from the INPUT_DATA directory
   inquire(file=trim(adjustl(full_file_name)),exist=file_exist) ! check if input file is there
   if (file_exist) then ! try to read it, if there is a grid provided
      open(newunit = FN, FILE = trim(adjustl(full_file_name)), status = 'old', action='read')
      ! Find the grid size from the file:
      call Count_lines_in_file(FN, Nsiz) ! module "Dealing_with_files"
      ! Knowing the size, create the grid-array and read from the file:
      if (allocated(numpar%At_bath_reset_grid)) deallocate(numpar%At_bath_reset_grid) ! make sure it's possible to allocate
      allocate(numpar%At_bath_reset_grid(Nsiz)) ! allocate it
      if (allocated(numpar%At_bath_grid_Ta)) deallocate(numpar%At_bath_grid_Ta) ! make sure it's possible to allocate
      allocate(numpar%At_bath_grid_Ta(Nsiz)) ! allocate it
      if (allocated(numpar%At_bath_grid_tau)) deallocate(numpar%At_bath_grid_tau) ! make sure it's possible to allocate
      allocate(numpar%At_bath_grid_tau(Nsiz)) ! allocate it

      ! Read data on the grid from the file:
      count_lines = 0   ! just to start counting lines in the file
      do i = 1, Nsiz    ! read grid line by line from the file
         read(FN,*,IOSTAT=Reason) numpar%At_bath_reset_grid(i), numpar%At_bath_grid_Ta(i), numpar%At_bath_grid_tau(i)
         call read_file(Reason, count_lines, read_well)    ! module "Dealing_with_files"
         if (.not. read_well) then ! something wrong with the user-defined grid
            write(Error_descript,'(a,i3)') 'In the file '//trim(adjustl(numpar%At_bath_step_grid_file))//' could not read line ', count_lines
            goto 9998  ! couldn't read the data, exit the cycle
         endif
      enddo
      numpar%i_At_bath_dt = 1 ! to start from
      read_well_out = .true.     ! we read the grid from the file well

9998 call close_file('close', FN=FN) ! module "Dealing_with_files"
   endif ! file_exist
end subroutine set_Bath_grid_atoms



subroutine read_user_additional_data(FN, count_lines, matter, Scell, NSC, user_data)
   integer, intent(in) :: FN  ! file to read from
   integer, intent(inout) :: count_lines  ! line we are reading
   type(Solid), intent(in) :: matter   ! all material parameters
   type(Super_cell), dimension(:), intent(inout) :: Scell  ! supercell with all the atoms as one object
   integer, intent(in) :: NSC ! number of supercell
   type(User_overwrite_data), intent(inout) :: user_data ! data to be read
   !--------------------------
   logical :: read_well
   integer :: Reason
   character(100) :: text

   ! Default values:
   user_data%do_overwrite = .false. ! to start with, no data to use

   read_well = .true.   ! to start with
   RD: do while (read_well)
      read(FN,*,IOSTAT=Reason) text
      call read_file(Reason, count_lines, read_well)
      if (.not. read_well) exit RD  ! end of file, stop reading

      call interpret_user_data(FN, count_lines, read_well, text, matter, Scell, NSC, user_data) ! below
      if (.not. read_well) exit RD  ! end of file, stop reading
   enddo RD

end subroutine read_user_additional_data


subroutine interpret_user_data(FN, count_lines, read_well, text, matter, Scell, NSC, user_data)
   integer, intent(in) :: FN  ! file to read from
   integer, intent(inout) :: count_lines  ! line we are reading
   logical, intent(inout) :: read_well ! marker if the line read well
   character(*), intent(in) :: text ! what was read in the previous line
   type(Solid), intent(in) :: matter	! all material parameters
   type(Super_cell), dimension(:), intent(inout) :: Scell  ! supercell with all the atoms as one object
   integer, intent(in) :: NSC ! number of supercell
   type(User_overwrite_data), intent(inout) :: user_data ! data to be read
   !-------------------------
   real(8) :: temp
   integer :: Nat, Nsh, i, temp_int(2), Reason
   character(3) :: temp_ch
   character(150) :: Error_descript

   ! Nat = size(matter%Atoms) ! number of atoms is unknown yet, use just some large value here:
   Nat = 100
   ! Find the maximal number of shells:
   Nsh = 0  ! to start with
   do i = 1, Nat
      !Nsh = max(Nsh, size(matter%Atoms(i)%Ip)) ! numer of shells is undefined yet!
      Nsh = 50
   enddo

   select case (trim(adjustl(text)))
   !--------------------------------
   case ('DRUDE', 'Drude', 'drude')
      ! initial n and k of unexcited material (used for DRUDE model only!):
      read(FN,*,IOSTAT=Reason) Scell(NSC)%eps%n, Scell(NSC)%eps%k	! initial n and k coeffs
      call read_file(Reason, count_lines, read_well)
      if (.not. read_well) then
         print*, 'Could not read line (#1)', count_lines, ' under "DRUDE" option'
         print*, 'Default values are used: n,k=', Scell(1)%eps%n, Scell(1)%eps%k
      endif

      ! [me] effective mass of CB electron and VB hole:
      read(FN,*,IOSTAT=Reason) Scell(NSC)%eps%me_eff, Scell(NSC)%eps%mh_eff
      call read_file(Reason, count_lines, read_well)
      if (.not. read_well) then
         print*, 'Could not read line (#2)', count_lines, ' under "DRUDE" option'
         print*, 'Default values are used: me,mh=', Scell(1)%eps%me_eff, Scell(1)%eps%mh_eff
      else
         Scell(NSC)%eps%me_eff = Scell(NSC)%eps%me_eff*g_me	! [kg]
         Scell(NSC)%eps%mh_eff = Scell(NSC)%eps%mh_eff*g_me	! [kg]
      endif

      ! [fs] mean scattering times of electrons and holes:
      read(FN,*,IOSTAT=Reason) Scell(NSC)%eps%tau_e, Scell(NSC)%eps%tau_h
      call read_file(Reason, count_lines, read_well)
      if (.not. read_well) then
         print*, 'Could not read line (#3)', count_lines, ' under "DRUDE" option'
         print*, 'Default values are used: te,th=', Scell(1)%eps%tau_e, Scell(1)%eps%tau_h
      endif

   !--------------------------------
   case ('NAME', 'Name', 'name')
      read(FN,*,IOSTAT=Reason) temp_int(1), temp_ch
      call read_file(Reason, count_lines, read_well)
      if (read_well) then
         if (.not.allocated(user_data%name)) then
            allocate(user_data%name(Nat))
            user_data%name = ''  ! to start with
         endif
         user_data%name(temp_int(1)) = temp_ch
         user_data%do_overwrite = .true.
      endif

   !--------------------------------
   case ('MASS', 'Mass', 'mass')
      read(FN,*,IOSTAT=Reason) temp_int(1), temp
      call read_file(Reason, count_lines, read_well)
      if (read_well) then
         if (.not.allocated(user_data%mass)) allocate(user_data%mass(Nat), source = -1.0d0)
         user_data%mass(temp_int(1)) = temp
         user_data%do_overwrite = .true.
      endif

   !--------------------------------
   case ('NO_AUGER', 'No_Auger', 'no_auger', 'Exclude_Auger', 'exclude_auger', 'EXCLUDE_AUGER')
      if (.not.allocated(user_data%auger)) allocate(user_data%auger(Nat,Nsh), source = 1.0d30)
      user_data%auger = 1.0d30   ! exclude Auger by setting time to infinity
      user_data%do_overwrite = .true.

   !--------------------------------
   case ('AUGER', 'Auger', 'auger')
      read(FN,*,IOSTAT=Reason) temp_int(:), temp
      call read_file(Reason, count_lines, read_well)
      if (read_well) then
         if (.not.allocated(user_data%auger)) allocate(user_data%auger(Nat,Nsh), source = -1.0d30)
         user_data%auger(temp_int(1),temp_int(2)) = temp
         user_data%do_overwrite = .true.
      endif
!       print*, 'AUGER', temp_int(1), temp_int(2), user_data%auger(temp_int(1),temp_int(2))
!       print*, 'SIZE:', size(user_data%auger,1), size(user_data%auger,2), Nat, Nsh
!       print*, 'ALL:', allocated(user_data%auger), user_data%auger(:,:)
!       pause 'AUGER'

   !--------------------------------
   case ('IP', 'Ip', 'ip', 'ionization_potential', 'Ionization_potential', 'IONIZATION_POTENTIAL')
      read(FN,*,IOSTAT=Reason) temp_int(:), temp
      call read_file(Reason, count_lines, read_well)
      if (read_well) then
         if (.not.allocated(user_data%Ip)) allocate(user_data%Ip(Nat,Nsh), source = -1.0d30)
         user_data%Ip(temp_int(1),temp_int(2)) = temp
         user_data%do_overwrite = .true.
      endif

   !--------------------------------
   case ('Ne', 'ne', 'NE', 'NUMBER_OF_ELECTRONS', 'Number_of_electrons', 'Population')
      read(FN,*,IOSTAT=Reason) temp_int(:), temp
      call read_file(Reason, count_lines, read_well)
      if (read_well) then
         if (.not.allocated(user_data%Ne_shell)) allocate(user_data%Ne_shell(Nat,Nsh), source = -1.0d0)
         user_data%Ne_shell(temp_int(1),temp_int(2)) = temp
         user_data%do_overwrite = .true.
      endif

   !--------------------------------
   case ('Ek', 'ek', 'EK', 'Kinetic_energy', 'KINETIC_ENERGY', 'kinetic_energy')
      read(FN,*,IOSTAT=Reason) temp_int(:), temp
      call read_file(Reason, count_lines, read_well)
      if (read_well) then
         if (.not.allocated(user_data%Ek)) allocate(user_data%Ek(Nat,Nsh), source = -1.0d30)
         user_data%Ek(temp_int(1),temp_int(2)) = temp
         user_data%do_overwrite = .true.
      endif
   end select

end subroutine interpret_user_data


subroutine overwrite_atomic_data(user_data, matter)
   type(User_overwrite_data), intent(in) :: user_data ! data to be read
   type(Solid), intent(inout) :: matter	! all material parameters
   !----------------------------
   integer :: i, Nat, j, Nsh

   ! Check if the user overwrite atomic data:
   if (user_data%do_overwrite) then
      Nat = size(matter%Atoms) ! number of atoms

      ! Element name:
      if (allocated(user_data%Name)) then
         do i = 1, Nat   ! check for all elements
            if (LEN(trim(adjustl(user_data%Name(i)))) > 0) then ! overwrite the name
               matter%Atoms(i)%Name = user_data%Name(i)
            endif
         enddo
      endif

      ! Mass:
      if (allocated(user_data%mass)) then
         do i = 1, Nat   ! check for all elements
            if (user_data%mass(i) > 0.0d0) then ! overwrite the mass
               matter%Atoms(i)%Ma = user_data%mass(i) * g_amu ! [kg]
            endif
         enddo
      endif

      ! Auger decay times:
      if (allocated(user_data%auger)) then
         do i = 1, Nat
            Nsh = size(matter%Atoms(i)%Ip)   ! number of shells
            do j = 1, Nsh
               if (user_data%Auger(i,j) > 0.0d0) then ! overwrite the auger decay time
                  matter%Atoms(i)%Auger(j) = user_data%auger(i,j) ! [fs]
               endif
            enddo ! j
         enddo ! i
      endif

      ! Ionization potentials:
      if (allocated(user_data%Ip)) then
         do i = 1, Nat
            Nsh = size(matter%Atoms(i)%Ip)   ! number of shells
            do j = 1, Nsh
               if (user_data%Ip(i,j) > 0.0d0) then ! overwrite the ionization potential
                  matter%Atoms(i)%Ip(j) = user_data%Ip(i,j) ! [eV]
               endif
            enddo ! j
         enddo ! i
      endif

      ! Kinetic energies of electronic in atomic shells:
      if (allocated(user_data%Ip)) then
         do i = 1, Nat
            Nsh = size(matter%Atoms(i)%Ek)   ! number of shells
            do j = 1, Nsh
               if (user_data%Ek(i,j) > 0.0d0) then ! overwrite the kinetic energy
                  matter%Atoms(i)%Ek(j) = user_data%Ek(i,j) ! [eV]
               endif
            enddo ! j
         enddo ! i
      endif

      ! Number of electrons in the atomic shell:
      if (allocated(user_data%Ip)) then
         do i = 1, Nat
            Nsh = size(matter%Atoms(i)%Ek)   ! number of shells
            do j = 1, Nsh
               if (user_data%Ne_shell(i,j) >= 0.0d0) then ! overwrite the electron population
                  matter%Atoms(i)%Ne_shell(j) = user_data%Ne_shell(i,j)
               endif
            enddo ! j
         enddo ! i
      endif

   endif ! (user_data%do_overwrite)
end subroutine overwrite_atomic_data


subroutine set_MD_step_grid(File_name, numpar, read_well_out, Error_descript)
   character(*), intent(in) :: File_name    ! file name with input data (or timestep of MD [fs])
   type(Numerics_param), intent(inout) :: numpar 	! all numerical parameters
   logical, intent(inout) :: read_well_out
   character(*), intent(inout) :: Error_descript
   !-----------------------------------------
   character(200) :: Path, full_file_name
   logical :: file_exist, read_well
   integer :: FN, Nsiz, count_lines, Reason, i

   read_well_out = .false.   ! to start with
   Path = trim(adjustl(m_INPUT_directory))//numpar%path_sep    ! where to find the file with the data
   full_file_name = trim(adjustl(Path))//trim(adjustl(File_name))   ! to read the file from the INPUT_DATA directory
   inquire(file=trim(adjustl(full_file_name)),exist=file_exist) ! check if input file is there
   if (file_exist) then ! try to read it, if there is a grid provided
      open(newunit = FN, FILE = trim(adjustl(full_file_name)), status = 'old', action='read')
      ! Find the grid size from the file:
      call Count_lines_in_file(FN, Nsiz) ! module "Dealing_with_files"
      ! Knowing the size, create the grid-array and read from the file:
      if (allocated(numpar%dt_MD_reset_grid)) deallocate(numpar%dt_MD_reset_grid) ! make sure it's possible to allocate
      allocate(numpar%dt_MD_reset_grid(Nsiz)) ! allocate it
      if (allocated(numpar%dt_MD_grid)) deallocate(numpar%dt_MD_grid) ! make sure it's possible to allocate
      allocate(numpar%dt_MD_grid(Nsiz)) ! allocate it

      ! Read data on the grid from the file:
      count_lines = 0   ! just to start counting lines in the file
      do i = 1, Nsiz    ! read grid line by line from the file
         read(FN,*,IOSTAT=Reason) numpar%dt_MD_reset_grid(i), numpar%dt_MD_grid(i)    ! grid data from the file
         call read_file(Reason, count_lines, read_well)    ! module "Dealing_with_files"
         if (.not. read_well) then ! something wrong with the user-defined grid
            write(Error_descript,'(a,i3)') 'In the file '//trim(adjustl(File_name))//' could not read line ', count_lines
            goto 9993  ! couldn't read the data, exit the cycle
         endif
      enddo
      read_well_out = .true.    ! we read the grid from the file well
      numpar%i_dt = 0   ! to start with
      numpar%dt = numpar%dt_MD_grid(1)   ! to start with

!       print*, 'set_MD_step_grid:'
!       print*, numpar%dt_MD_reset_grid(:)
!       print*, 'dt=', numpar%dt_MD_grid(:)

9993 call close_file('close', FN=FN) ! module "Dealing_with_files"
   else ! If there is no input file, check if the teimstep is provided instead:
      count_lines = 0   ! just to start counting lines in the file
      read(File_name,*,IOSTAT=Reason) numpar%dt  ! Time step for MD [fs]
      call read_file(Reason, count_lines, read_well)    ! module "Dealing_with_files"
      if (read_well) read_well_out = .true.    ! we read the grid from the file well
      numpar%i_dt = -1   ! to mark that the reset option is unused
      ! Set often-used values:
   endif ! file_exist
   numpar%halfdt = numpar%dt/2.0d0           ! dt/2, often used
   numpar%dtsqare = numpar%dt*numpar%halfdt  ! dt*dt/2, often used
   numpar%dt3 = numpar%dt**3/6.0d0           ! dt^3/6, often used
   numpar%dt4 = numpar%dt*numpar%dt3/8.0d0   ! dt^4/48, often used

!    pause 'set_MD_step_grid'
end subroutine set_MD_step_grid



subroutine read_input_material(File_name, Scell, matter, numpar, laser, Err)
   type(Super_cell), dimension(:), allocatable, intent(inout) :: Scell ! suoer-cell with all the atoms inside
   character(*), intent(in) :: File_name
   type(Solid), intent(inout) :: matter	! all material parameters
   type(Numerics_param), intent(inout) :: numpar 	! all numerical parameters
   type(Pulse), dimension(:), allocatable, intent(inout) :: laser	! Laser pulse parameters
   type(Error_handling), intent(inout) :: Err	! error save
   real(8) read_var(3) ! just to read variables from file
   integer FN, N, Reason, count_lines, i
   logical file_opened, read_well
   character(100) Error_descript, text

   !open(NEWUNIT=FN, FILE = trim(adjustl(File_name)), status = 'old')
   FN=109
   open(UNIT=FN, FILE = trim(adjustl(File_name)), status = 'old', action='read')
   inquire(file=trim(adjustl(File_name)),opened=file_opened)
   if (.not.file_opened) then
      Error_descript = 'File '//trim(adjustl(File_name))//' could not be opened, the program terminates'
      call Save_error_details(Err, 2, Error_descript)
      print*, trim(adjustl(Error_descript))
      goto 3417
   endif

   ! Material name:
   read(FN,*,IOSTAT=Reason) matter%Name
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i5,a,$)') 'Could not read line ', count_lines, ' in file '//trim(adjustl(File_name))
      call Save_error_details(Err, 3, Error_descript)
      print*, trim(adjustl(Error_descript))
      goto 3417
   endif

   ! chemical formula of the compound (used in MC in case of EADL parameters):
   read(FN,*,IOSTAT=Reason) matter%Chem
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i5,a,$)') 'Could not read line ', count_lines, ' in file '//trim(adjustl(File_name))
      call Save_error_details(Err, 3, Error_descript)
      print*, trim(adjustl(Error_descript))
      goto 3417
   endif

   if (.not.allocated(Scell)) allocate(Scell(1)) ! just for start, 1 supercell
   do i = 1, size(Scell) ! for all supercells

      ! initial electron temperature [K] or filename with the distribution function:
      read(FN,*,IOSTAT=Reason) Scell(i)%Te
      if (Reason == 0) then ! there was a number, interpret it as electronic temperature
         call read_file(Reason, count_lines, read_well)
         if (.not. read_well) then
            write(Error_descript,'(a,i5,a,$)') 'Could not read line ', count_lines, ' in file '//trim(adjustl(File_name))
            call Save_error_details(Err, 3, Error_descript)
            print*, trim(adjustl(Error_descript))
            goto 3417
         endif
         numpar%fe_filename = '' ! user provided no filename for distribution (use Fermi with given tempreature instead)
      else ! maybe there was a name of the file with electronic distribution:
         Scell(i)%Te = -1.0d0 ! Just to indicate nonequilibrium distribution
         backspace(FN)  ! get back and try to read the line again:
         count_lines = count_lines - 1
         read(FN,*,IOSTAT=Reason) numpar%fe_filename  ! read filename
         call read_file(Reason, count_lines, read_well)
         if (.not. read_well) then
            write(Error_descript,'(a,i5,a,$)') 'Could not read line ', count_lines, ' in file '//trim(adjustl(File_name))
            call Save_error_details(Err, 3, Error_descript)
            print*, trim(adjustl(Error_descript))
            goto 3417
         endif
      endif
      Scell(i)%TeeV = Scell(i)%Te/g_kb ! [eV] electron temperature

      ! initial atomic temperature [K]:
      read(FN,*,IOSTAT=Reason) Scell(i)%Ta	
      call read_file(Reason, count_lines, read_well)
      if (.not. read_well) then
         write(Error_descript,'(a,i5,a,$)') 'Could not read line ', count_lines, ' in file '//trim(adjustl(File_name))
         call Save_error_details(Err, 3, Error_descript)
         print*, trim(adjustl(Error_descript))
         goto 3417
      endif
      Scell(i)%TaeV = Scell(i)%Ta/g_kb ! [eV] atomic temperature
   enddo !Scell

   ! Start of the simulation [fs]:
   read(FN,*,IOSTAT=Reason) numpar%t_start
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i5,a,$)') 'Could not read line ', count_lines, ' in file '//trim(adjustl(File_name))
      call Save_error_details(Err, 3, Error_descript)
      print*, trim(adjustl(Error_descript))
      goto 3417
   endif

   ! total duration of simulation [fs]:
   read(FN,*,IOSTAT=Reason) numpar%t_total	
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i5,a,$)') 'Could not read line ', count_lines, ' in file '//trim(adjustl(File_name))
      call Save_error_details(Err, 3, Error_descript)
      print*, trim(adjustl(Error_descript))
      goto 3417
   endif

   ! Laser parameters:
   read(FN,*,IOSTAT=Reason) N		! How many pulses
   call read_file(Reason, count_lines, read_well)
   if (.not. read_well) then
      write(Error_descript,'(a,i5,a,$)') 'Could not read line ', count_lines, ' in file '//trim(adjustl(File_name))
      call Save_error_details(Err, 3, Error_descript)
      print*, trim(adjustl(Error_descript))
      goto 3417
   endif
   ! For multiple pulses, parameters for each:
   PULS:if (N >= 0) then ! If there is at least one pulse:
    if (allocated(laser)) deallocate(laser)
    allocate(laser(N))  ! that's how many pulses
    do i = 1, N         ! read parameters for all pulses
      read_var = 0.0d0 ! to start with
      read(FN,*,IOSTAT=Reason) read_var(:)
      if (Reason == 0) then ! three numbers are given, set few inputs with varying dose:
         call read_file(Reason, count_lines, read_well)  ! to keep proper counting of lines, do this
         if (.not. read_well) then
            write(Error_descript,'(a,i5,a,$)') 'Could not read line ', count_lines, ' in file '//trim(adjustl(File_name))
            call Save_error_details(Err, 3, Error_descript)
            print*, trim(adjustl(Error_descript))
            goto 3417
         endif
         ! For this simulation run, use the first value given:
         laser(i)%F = read_var(1)   ! ABSORBED DOSE IN [eV/atom]
         ! For other simulation runs, create the input files accordingly:
         call prepare_multiple_inputs(numpar, File_name, read_var)  ! below

      else ! probably, there weren't three parameters in the line, so read just the fluence
         backspace(FN)  ! get back and try to read the line again:
         count_lines = count_lines - 1
         read(FN,*,IOSTAT=Reason) laser(i)%F	  ! ABSORBED DOSE IN [eV/atom]
         call read_file(Reason, count_lines, read_well)
         if (.not. read_well) then
            write(Error_descript,'(a,i5,a,$)') 'Could not read line ', count_lines, ' in file '//trim(adjustl(File_name))
            call Save_error_details(Err, 3, Error_descript)
            print*, trim(adjustl(Error_descript))
            goto 3417
         endif
      endif

      read(FN,*,IOSTAT=Reason) laser(i)%hw, laser(i)%FWHM_hw  ! photon energy in [eV], and FWHM width of distribution [eV]
      if (Reason /= 0) then ! probably only energy provided, not the distribution width, so assume FWHM_hw=0
         laser(i)%FWHM_hw = 0.0d0
         backspace(FN)  ! get back and try to read the line again:
         count_lines = count_lines - 1
         read(FN,*,IOSTAT=Reason) laser(i)%hw  ! photon energy in [eV] only, no distribution
         call read_file(Reason, count_lines, read_well)
      endif
      if (.not. read_well) then
         write(Error_descript,'(a,i5,a,$)') 'Could not read line ', count_lines, ' in file '//trim(adjustl(File_name))
         call Save_error_details(Err, 3, Error_descript)
         print*, trim(adjustl(Error_descript))
         goto 3417
      endif

      read(FN,*,IOSTAT=Reason) laser(i)%t	  ! PULSE FWHM-DURATION IN [fs]
      call read_file(Reason, count_lines, read_well)
      if (.not. read_well) then
         write(Error_descript,'(a,i5,a,$)') 'Could not read line ', count_lines, ' in file '//trim(adjustl(File_name))
         call Save_error_details(Err, 3, Error_descript)
         print*, trim(adjustl(Error_descript))
         goto 3417
      endif

      read(FN,*,IOSTAT=Reason) laser(i)%KOP ! type of pulse: 0=rectangular, 1=Gaussian, 2=SASE
      call read_file(Reason, count_lines, read_well)
      if (.not. read_well) then
         write(Error_descript,'(a,i5,a,$)') 'Could not read line ', count_lines, ' in file '//trim(adjustl(File_name))
         call Save_error_details(Err, 3, Error_descript)
         print*, trim(adjustl(Error_descript))
         goto 3417
      endif

      read(FN,*,IOSTAT=Reason) laser(i)%t0  ! POSITION OF THE MAXIMUM OF THE PULSE IN [fs]
      call read_file(Reason, count_lines, read_well)
      if (.not. read_well) then
         write(Error_descript,'(a,i5,a,$)') 'Could not read line ', count_lines, ' in file '//trim(adjustl(File_name))
         call Save_error_details(Err, 3, Error_descript)
         print*, trim(adjustl(Error_descript))
         goto 3417
      endif

      if (laser(i)%KOP .EQ. 1) laser(i)%t = laser(i)%t/2.35482	! make a gaussian parameter out of it
     enddo ! have read parameters for all pulses
   endif PULS
   

   !------------------------------------------------
   ! Check if there are additional options provided:
   read_well = .true.   ! to start with
   RDID: do while (read_well)
      read(FN,*,IOSTAT=Reason) text
      call read_file(Reason, count_lines, read_well)
      if (.not. read_well) exit RDID  ! end of file, stop reading

      call interpret_user_data_INPUT(FN, trim(adjustl(File_name)), count_lines, text, Scell, numpar, Err) ! below
      if (Err%Err) goto 3417
   enddo RDID

   if (numpar%verbose) call print_time_step('Verbose option is on, XTANT is going to be a chatterbox', msec=.true.) ! modlue "Little_subroutines"

   ! Close this file, it has been read through:
3417  if (file_opened) close(FN)
end subroutine read_input_material


subroutine interpret_user_data_INPUT(FN, File_name, count_lines, string, Scell, numpar, Err) ! below
   integer, intent(in) :: FN  ! file to read from
   character(*), intent(in) :: File_name
   integer, intent(inout) :: count_lines  ! line we are reading
   character(*), intent(in) :: string ! what was read in the previous line
   type(Super_cell), dimension(:), allocatable, intent(inout) :: Scell ! suoer-cell with all the atoms inside
   type(Numerics_param), intent(inout) :: numpar 	! all numerical parameters
   type(Error_handling), intent(inout) :: Err	! error save
   !--------------------------
   real(8), dimension(3) :: read_var   ! fluence: starting, ending, step; all in [eV/atom]
   integer :: Reason, num_phon, i, N
   logical :: read_well
   character(200) :: Error_descript

   read_well = .true.   ! to start with
   read_var = 0.0d0     ! unused variable in this case

   select case (trim(adjustl(string)))
   case ('el-ph', 'EL-PH', 'El-Ph', 'Coupling', 'COUPLING', 'coupling')
      read(FN,*,IOSTAT=Reason) num_phon   ! number of simulations for average electron-phonon coupling parameter
      call read_file(Reason, count_lines, read_well)
      if (read_well) then ! pass the number of simulations
         call prepare_multiple_inputs(numpar, File_name, read_var, .true., num_phon, string=trim(adjustl(string)))   ! below
      else ! use default nuber of iterations
         call prepare_multiple_inputs(numpar, File_name, read_var, .true., string=trim(adjustl(string))) ! below
      endif

   case ('WATER', 'EMBED_WATER', 'EMBED_IN_WATER', 'Water', 'water', 'embed_water', 'Embed_Water', 'Embed_in_water')
      numpar%embed_water = .true.   ! save the flag for water embedding
      read(FN,*,IOSTAT=Reason) numpar%N_water_mol   ! number of water molecules to use
      call read_file(Reason, count_lines, read_well)
      if (.not. read_well) then
         numpar%N_water_mol = 100 ! use default
      elseif (numpar%N_water_mol < 0) then   ! don't use water
         numpar%embed_water = .false.
         numpar%N_water_mol = 0
      endif

   case ('PROBE', 'Probe', 'probe')

      ! Calculate optical parameters, and with which model:
      read(FN,*,IOSTAT=Reason) numpar%optic_model, N, read_var
      if (.not. read_well) then
         write(Error_descript,'(a,i5,a,$)') 'Could not read line ', count_lines, ' in file '//trim(adjustl(File_name))
         call Save_error_details(Err, 3, Error_descript)
         print*, trim(adjustl(Error_descript))
         return
      endif
      SCL:do i = 1, size(Scell) ! for all supercells
         if (numpar%optic_model .GT. 0) then ! yes, calculate optical coefficients:
            numpar%do_drude = .true.	! included
            Scell(i)%eps%KK = .false.	! no K-K relations
            if (N == 2) then	! use Kramers Kronig relations for spectrum
               Scell(i)%eps%KK = .true.
               Scell(i)%eps%all_w = .true.
            elseif (N == 1) then	! calculate spectrum, but directly, without using Kramers Kronig relations
               Scell(i)%eps%all_w = .true.
            else
               Scell(i)%eps%all_w = .false.
            endif
         else
            numpar%do_drude = .false.	! not included
         endif

         Scell(i)%eps%E_min = read_var(1) ! starting point of the grid of energy [eV]
         Scell(i)%eps%E_max = read_var(2) ! ending point of the grid of energy [eV]
         Scell(i)%eps%dE = read_var(3)    ! grid step of energy [eV]

         ! Absorbtion of how many rays (0=exclude, 1=1st ray, (>1)=sum all); probe-pulse wavelength [nm]; probe duration FWHM [fs]
         read(FN,*,IOSTAT=Reason) numpar%drude_ray, Scell(i)%eps%l, Scell(i)%eps%tau
         if (.not. read_well) then
            write(Error_descript,'(a,i5,a,$)') 'Could not read line ', count_lines, ' in file '//trim(adjustl(File_name))
            call Save_error_details(Err, 3, Error_descript)
            print*, trim(adjustl(Error_descript))
            return
         endif
         !if (.not.numpar%do_drude) Scell(i)%eps%tau = -0.0d0 ! to exclude convolution if there is no probe pulse
         Scell(i)%eps%ReEps0 = 0.0d0	! to start with
         Scell(i)%eps%ImEps0 = 0.0d0	! to start with
         Scell(i)%eps%w = 2.0d0*g_Pi*g_cvel/(Scell(i)%eps%l*1d-9) ! [1/sec] frequency

         ! Angle of prob-pulse with respect to normal [degrees]; material thickness [nm]:
         read(FN,*,IOSTAT=Reason) Scell(i)%eps%teta, Scell(i)%eps%dd
         if (.not. read_well) then
            write(Error_descript,'(a,i5,a,$)') 'Could not read line ', count_lines, ' in file '//trim(adjustl(File_name))
            call Save_error_details(Err, 3, Error_descript)
            print*, trim(adjustl(Error_descript))
            return
         endif
         Scell(i)%eps%teta = Scell(i)%eps%teta*g_Pi/(180.0d0) !c [radians]
      enddo SCL

   case default
      ! Check if the user needs any additional info (by setting the flags):
      call interprete_additional_data(string, numpar%path_sep, change_size=numpar%change_size, contin=Err%Err, &
                  allow_rotate=numpar%allow_rotate, verbose=numpar%verbose) ! module "Read_input_data"

   endselect
end subroutine interpret_user_data_INPUT



subroutine prepare_multiple_inputs(numpar, File_name, read_var, do_eph, num_phon, string)
   type(Numerics_param), intent(in) :: numpar 	! all numerical parameters
   character(*), intent(in) :: File_name  ! given filename
   real(8), dimension(3), intent(in) :: read_var   ! fluence: starting, ending, step; all in [eV/atom]
   logical, intent(in), optional :: do_eph  ! for electron-phonon coupling, it requires special multiple input
   integer, intent(in), optional :: num_phon ! how many simulation for average electron-phonon coupling
   character(*), intent(in), optional :: string
   !-----------------------------------
   real(8) :: dose_cur, RN, x_cur, x_0, pulse
   integer :: N, i, FN, FN2, file_len, count_lines, j, N_lines, Reason, sz
   character(250) :: Save_file, Cur_file, Num_par_file
   character(250), allocatable, dimension(:) :: File_content
   character(5) :: chtest2
   character(25) :: chtest
   logical :: read_well, do_el_phon

   ! Check, if user requested average electron-phonon coupling calculations:
   if (present(do_eph)) then
      do_el_phon = do_eph
   else  ! not average electron-phonon calculations
      do_el_phon = .false.
   endif

   ! Check, if it is fluence grid, or electron-phonon grid:
   if (do_el_phon) then
      if (present(num_phon)) then   ! user provided number of points
         N = num_phon-1
         if (N < 1) N = 0
      else  ! use default value:
         N = 10
      endif
   else ! then must be the fluence points:
      ! Get the total number of fluence points:
      N = ceiling(abs(read_var(2) - read_var(1))/abs(read_var(3)))
   endif

   ! Set the name of the numerical_parameters file:
   Num_par_file = trim(adjustl(numpar%input_path))//trim(adjustl(m_NUMERICAL_PARAMETERS))//'.txt'

   ! Set temporary file name:
   file_len = LEN(trim(adjustl(File_name)))  ! length of the string
   Save_file = trim(adjustl(File_name(1:file_len-4)))//'_SAVE.txt'

   ! Create the temporary save file
   if (numpar%path_sep .EQ. '\') then	! if it is Windows
      call copy_file(File_name, Save_file, 1, add_com='* /YQ') ! module "Dealing_with_files"
   else
      call copy_file(File_name, Save_file) ! module "Dealing_with_files"
   endif

   ! Open the file:
   FN=4000
   open(UNIT=FN, FILE = trim(adjustl(Save_file)), status = 'old', action='read')
   call Count_lines_in_file(FN, N_lines)  ! module "Dealing_with_files"
   ! Knowing the size, allocate the array:
   allocate(File_content(N_lines))
   ! Read the saved file:
   count_lines = 0   ! to start with
   do j = 1, N_lines
      read(FN, '(a)', IOSTAT=Reason) File_content(j)   ! read the current line
      call read_file(Reason, count_lines, read_well)   ! modlue "Dealing_with_files"
      if ( (.not.read_well) .and. (numpar%path_sep == '/') ) then ! if it is Linux
         backspace(FN)  ! to reread the line
         count_lines = count_lines - 1 ! reread the same line, don't count it as the next one
         read(FN, '(a)', IOSTAT=Reason) File_content(j)(1:sz) ! read it again, now knowing the size
         call read_file(Reason, count_lines, read_well) ! modlue "Dealing_with_files"
      endif
      if (.not.read_well) then
         print*, 'Problem in prepare_multiple_inputs: cannot read line ', count_lines, ' in file '//trim(adjustl(Cur_file))
         goto 3440
      endif
   enddo
   ! Close files:
   call close_file('delete', FN=FN) ! module "Dealing_with_files"

   ! Make a new copy of the input file with the changed fluence only:
   do i = 1, N
      ! Set the new dose:
      !dose_cur = min(read_var(1),read_var(2)) + dble(i)*abs(read_var(3))
      dose_cur = read_var(1) + dble(i) * sign( read_var(3), (read_var(2)-read_var(1)) )

      ! Set the new file name:
      FN2=FN+i
      write(chtest2,'(i5)') i
      Cur_file = trim(adjustl(File_name(1:file_len-4)))//'_'//trim(adjustl(chtest2))//'.txt'
      open(UNIT=FN2, FILE = trim(adjustl(Cur_file)))

      ! Copy data into this new file, accept for the fluence line:
      do j = 1, N_lines

         if (do_el_phon) then ! it is electron-phonon calculations, requires changing a few parameters:
            select case (j)
            case default
               if (present(string)) then
                  if (trim(adjustl(File_content(j))) /= string) then ! don't make extra copies of the file
                     write(FN2, '(a)') trim(adjustl(File_content(j)))   ! just copy this line
                  endif
               else
                  write(FN2, '(a)') trim(adjustl(File_content(j)))   ! just copy this line
               endif
            case (5) ! start of simulation [fs]
               ! Get the user-provided simulation time:
               read( File_content(j), *, IOSTAT=Reason) x_0
               ! Sample randomly simulation starting time:
               call random_number(RN)  ! [0:1]
               x_cur = x_0 * (1.0d0 + 0.2d0*(RN-0.5d0))
               write(chtest, '(f16.5)') x_cur
               write(FN2, '(a,a)') trim(adjustl(chtest)), '          ! start of simulation [fs]'
            case (6) ! end of simulation [fs]
               ! Get the user-provided simulation time:
               read( File_content(j), *, IOSTAT=Reason) x_0
               ! Sample randomly simulation starting time:
               call random_number(RN)  ! [0:1]
               x_cur = x_0 * (1.0d0 + 0.5d0*(RN-0.5d0))
               pulse = x_cur  ! save it for later, to set pulse duration equal to this value
               write(chtest, '(f16.5)') x_cur
               write(FN2, '(a,a)') trim(adjustl(chtest)), '          ! end of simulation time [fs]'
            case (8) ! absorbed dose per this pulse [eV/atom] (min, max, step)
               ! Get the user-provided simulation time:
               read( File_content(j), *, IOSTAT=Reason) x_0
               ! Sample randomly simulation starting time:
               call random_number(RN)  ! [0:1]
               x_cur = x_0 * (1.0d0 + 0.2d0*(RN-0.5d0))
               write(chtest, '(f16.5)') x_cur
               write(FN2, '(a,a)') trim(adjustl(chtest)), '          ! absorbed dose per this pulse [eV/atom]'
            case (10)   ! pulse FWHM-duration [fs]
               write(chtest, '(f16.5)') pulse
               write(FN2, '(a,a)') trim(adjustl(chtest)), '          ! pulse FWHM-duration [fs]'
            end select

         else ! it is fluence grid:
            if (j == 8) then  ! dose is set in the line #8
               write(chtest, '(f16.5)') dose_cur
               write(FN2, '(a,a)') trim(adjustl(chtest)), '          ! absorbed dose [eV/atom]'
            else  ! not the dose
               if (present(string)) then
                  if (trim(adjustl(File_content(j))) /= string) then ! don't make extra copies of the file
                     write(FN2, '(a)') trim(adjustl(File_content(j)))   ! just copy this line
                  endif
               else
                  write(FN2, '(a)') trim(adjustl(File_content(j)))   ! just copy this line
               endif
            endif
         endif ! (do_el_phon)
      enddo ! j = 1, N_lines

      call close_file('close', FN=FN2) ! module "Dealing_with_files"

      ! Also, make a copy of the numerical_parameters file:
      Cur_file = trim(adjustl(numpar%input_path))//trim(adjustl(m_NUMERICAL_PARAMETERS))
      write(Cur_file,'(a,a,a,a)') trim(adjustl(Cur_file)), '_', trim(adjustl(chtest2)), '.txt'
      ! Create the temporary save file
      if (numpar%path_sep .EQ. '\') then	! if it is Windows
         call copy_file(Num_par_file, Cur_file, 1, add_com='* /YQ') ! module "Dealing_with_files"
      else
         call copy_file(Num_par_file, Cur_file) ! module "Dealing_with_files"
      endif
   enddo

3440 continue
end subroutine prepare_multiple_inputs






! Reads additional data from the command line passed along with the XTANT:
subroutine get_add_data(path_sep, change_size, contin, allow_rotate, verbose)
   character(1), intent(inout) :: path_sep
   logical, intent(inout) :: change_size
   logical, intent(out) :: contin
   logical, intent(out) :: allow_rotate
   logical, intent(out) :: verbose
   !---------------
   character(1000) :: string
   integer :: i_arg, count_args, N_arg
   logical :: read_well

   ! Default values:
   change_size = .false. ! don't do changing size
   verbose = .false.   ! don't print a lot of stuff

   ! Identify the OS by the system-used path separator:
   call Path_separator(path_sep) ! module "Dealing_with_files"

   ! Count how many arguments the user provided:
   N_arg = COMMAND_ARGUMENT_COUNT() ! Fortran intrinsic function

   read_well = .true.   ! to start with
   count_args = 0 ! to start with

   ALLARG:do i_arg = 1, N_arg ! read all the arguments passed
      ! Read the argument provided:
      call GET_COMMAND_ARGUMENT(i_arg,string)  ! intrinsic

      ! Act on the command passed:
      call interprete_additional_data(string, path_sep, change_size, contin, allow_rotate, verbose)  ! below

   enddo ALLARG
end subroutine get_add_data


subroutine interprete_additional_data(string, path_sep, change_size, contin, allow_rotate, verbose)
   character(*), intent(in) :: string
   character(1), intent(inout) :: path_sep
   logical, intent(inout), optional :: change_size
   logical, intent(out), optional :: contin
   logical, intent(out), optional :: allow_rotate
   logical, intent(out), optional :: verbose
   !---------------
   character(1000) :: read_string, printline, ch_temp, string_read
   character(200) :: file_name
   integer :: FN, Reason, count_lines
   logical :: file_opened, read_text_well, read_well, file_exists

   string_read = trim(adjustl(string))
   ! Trim minus signs if present (for legacy reasons):
   do while (string_read(1:1) == '-')
      string_read = string_read(2:)
   enddo

   ! Interpret the command:
   select case (trim(adjustl(string_read)))
   case ('verbose', 'VERBOSE', 'Verbose')
      print*, 'XTANT will print a lot of markers for testing and debugging'
      if (present(verbose)) verbose = .true.
      write(*,'(a)') trim(adjustl(m_starline))

   case ('allow_rotation', 'allow_rotate', 'no_ang_removal')
      print*, 'The angular momenta of the sample will not be removed'
      if (present(allow_rotate)) allow_rotate = .true. ! don't remove angular momentum from initial conditions
      write(*,'(a)') trim(adjustl(m_starline))

   case ('size', 'Size', 'SIZE')
      print*, 'Supercell size variation will be performed to plot potential energy curve'
      if (present(change_size)) change_size = .true. ! do changing size
      write(*,'(a)') trim(adjustl(m_starline))

   case ('test', 'TEST', 'Test')
      print*, 'Wow, it really works!'
      !if (present(contin)) contin = .false.
      write(*,'(a)') trim(adjustl(m_starline))

   case ('Matter', 'matter', 'MATTER', 'Materials', 'materials', 'list', 'LIST', 'List')
      write(*,'(a)') trim(adjustl(m_starline))
      ! Create file with list of available materials:
      call Get_list_of_materials(path_sep)  ! below

      write(*,'(a)') trim(adjustl(m_starline))
      if (present(contin)) contin = .true.  ! stop calculations, user only wanted some info

   case ('help', 'HELP', 'Help')
      ! Filename with help:
      file_name = trim(adjustl(m_INPUT_directory))//path_sep//trim(adjustl(m_INFO_directory))//path_sep//trim(adjustl(m_HELP_file))

      inquire(file=trim(adjustl(file_name)),exist=file_exists)
      if (.not.file_exists) then ! no file, cannot print help
         write(*,'(a)') 'Could not find file ', trim(adjustl(file_name))
         write(*,'(a)') 'Cannot help, sorry. Read the manual.'
      else ! (.not.file_exists)
         FN=200
         open(UNIT=FN, FILE = trim(adjustl(file_name)), status = 'old', action='READ')
         inquire(file=trim(adjustl(file_name)),opened=file_opened)
         if (.not.file_opened) then
            write(*,'(a)') 'Could not open file ', trim(adjustl(file_name))
            write(*,'(a)') 'Cannot help, sorry. Read the manual.'
         else ! (.not.file_opened)
            read_text_well = .true. ! to start with
            count_lines = 0   ! to start with
            do while (read_text_well)
               read(FN,'(a)',IOSTAT=Reason) printline
               call read_file(Reason, count_lines, read_text_well)   ! module "Dealing_with_files"
               if (Reason > 0) then   ! something wrong in the line
                  write(*,'(a)') 'Problem reading file '//trim(adjustl(file_name))
                  write(ch_temp, '(i)') count_lines
                  write(*,'(a)') 'in line '//trim(adjustl(ch_temp))
                  read_well = .false.
               elseif (Reason < 0) then ! end of file reached ...
                  close(FN)
               else
                  write(*,'(A)') trim(adjustl(printline))
               endif
            enddo
         endif ! (.not.file_opened)
      endif ! (.not.file_exists)

      write(*,'(a)') trim(adjustl(m_starline))
      if (present(contin)) contin = .true.  ! stop calculations, user only wanted some help
   case ('info', 'INFO', 'Info')
      ! Filename with help:
      file_name = trim(adjustl(m_INPUT_directory))//path_sep//trim(adjustl(m_INFO_directory))//path_sep//trim(adjustl(m_INFO_file))

      inquire(file=trim(adjustl(file_name)),exist=file_exists)
      if (.not.file_exists) then ! no file, cannot print help
         write(*,'(a)') 'Could not find file ', trim(adjustl(file_name))
         write(*,'(a)') 'Cannot help, sorry. Read the manual.'
      else ! (.not.file_exists)
         FN=201
         open(UNIT=FN, FILE = trim(adjustl(file_name)), status = 'old', action='READ')
         inquire(file=trim(adjustl(file_name)),opened=file_opened)
         if (.not.file_opened) then
            write(*,'(a)') 'Could not open file ', trim(adjustl(file_name))
            write(*,'(a)') 'Cannot help, sorry. Read the manual.'
         else ! (.not.file_opened)
            read_text_well = .true. ! to start with
            count_lines = 0   ! to start with
            do while (read_text_well)
               read(FN,'(a)',IOSTAT=Reason) printline
               call read_file(Reason, count_lines, read_text_well)   ! module "Dealing_with_files"
               if (Reason > 0) then   ! something wrong in the line
                  write(*,'(a)') 'Problem reading file '//trim(adjustl(file_name))
                  write(ch_temp, '(i)') count_lines
                  write(*,'(a)') 'in line '//trim(adjustl(ch_temp))
                  read_well = .false.
               elseif (Reason < 0) then ! end of file reached ...
                  close(FN)
               else
                  write(*,'(A)') trim(adjustl(printline))
               endif
            enddo
         endif ! (.not.file_opened)
      endif ! (.not.file_exists)

      write(*,'(a)') trim(adjustl(m_starline))
      if (present(contin)) contin = .true.  ! stop calculations, user only wanted some info
   case default
   end select
end subroutine interprete_additional_data


subroutine Get_list_of_materials(path_sep)
   character(*), intent(in) :: path_sep ! file name
   !--------------------
   integer :: FN_temp, FN, count_lines, Reason, i, open_status, iret
   character(200) :: Error_descript, File_name, read_line, command, File_scratch
   logical :: file_opened, file_exist

   File_scratch = trim(adjustl(m_INPUT_directory))//path_sep//'Scratch.txt'
   File_name = trim(adjustl(m_INPUT_directory))//path_sep//trim(adjustl(m_List_ofmaterials))

   ! Make a list of the materials available:
   if (path_sep == '\') then	! if it is Windows
      command = 'dir '//trim(adjustl(m_INPUT_directory))//' /b > '//trim(adjustl(File_scratch))
   else ! linux:
      command = "ls -t "//trim(adjustl(m_INPUT_directory))//" > "//trim(adjustl(File_scratch))
   endif
#ifdef OMP_inside
   iret = system(trim(adjustl(command)))   ! execute the command to save file names in the temp file
#else
   call system(trim(adjustl(command))) ! execute the command to save file names in the temp file
#endif

   FN=200
   open(UNIT=FN, FILE = trim(adjustl(File_name)))
   inquire(file=trim(adjustl(File_name)),opened=file_opened)
   if (.not.file_opened) then
      write(*,'(a)') 'Could not open file ', trim(adjustl(File_name))
      write(*,'(a)') 'Cannot help, sorry. Check materials manually.'
      goto 9992
   endif

   ! Open the files with directory names:
   open(NEWUNIT=FN_temp, file=trim(adjustl(File_scratch)), iostat=open_status, action='read')
   if ( open_status /= 0 ) then
      print *, 'Could not open ',trim(adjustl(File_scratch)),' for listing.', ' Unit = ', FN_temp
      write(*,'(a)') 'Cannot help, sorry. Check materials manually.'
      goto 9992
   endif

   ! Printout the list of materials:
   write(*,'(a)') ' Materials already available in XTANT:'
   count_lines = 0   ! to start with
   RDLST:do
      read(FN_temp,'(a)',IOSTAT=Reason) read_line
      count_lines = count_lines + 1
      if (Reason < 0) then ! end of file
         exit RDLST
      else  ! line in the fil
         ! Check if the line is commented out:
         if (trim(adjustl(read_line(1:1))) == '!') then ! it is a comment
            ! ignor this folder / file
         else ! don't ignore this name
            ! Check if it is a directory:
            inquire(DIRECTORY=trim(adjustl(m_INPUT_directory))//path_sep//trim(adjustl(read_line)), exist=file_exist)
            if (file_exist) then ! if it is a directory, it means it can be a material:
               select case ( trim(adjustl(read_line)) )  ! check if it is material or just forled
               case (m_Atomic_parameters, m_INFO_directory, m_HELP_file, m_DFTB_directory, m_DFTB_norep_directory, &
                  m_3TB_directory, m_BOP_directory, m_xTB_directory) ! work directory, not a material
                  ! skip this line
               case default   ! material name
                  write(FN,'(a)') trim(adjustl(read_line))  ! save in the file
                  write(*,'(a)') trim(adjustl(read_line))   ! print on the screen
               endselect
            endif ! (file_exist)
         endif ! (trim(adjustl(read_line)) == '!')
      endif ! (Reason < 0)
   enddo RDLST

9992 continue
   call close_file('delete', trim(adjustl(File_scratch)))   ! module "Dealing_with_files"
   call close_file('close', FN=FN)  ! module "Dealing_with_files"
end subroutine Get_list_of_materials


!---------------------------------------------
! Alternative format of input file:

subroutine read_input_txt(File_name, Scell, matter, numpar, laser, Err)
   character(*), intent(in) :: File_name
   type(Solid), intent(inout) :: matter	! all material parameters
   type(Numerics_param), intent(inout) :: numpar 	! all numerical parameters
   type(Pulse), dimension(:), allocatable, intent(inout) :: laser	! Laser pulse parameters
   type(Super_cell), dimension(:), allocatable, intent(inout) :: Scell ! suoer-cell with all the atoms inside
   type(Error_handling), intent(inout) :: Err	! error save
   !--------------------------------------------------------
   integer :: FN, count_lines, Reason, i
   character(200) :: Error_descript, read_line
   logical :: file_opened
   FN=110
   open(UNIT=FN, FILE = trim(adjustl(File_name)), status = 'old', action='read')
   inquire(file=trim(adjustl(File_name)),opened=file_opened)
   if (.not.file_opened) then
      Error_descript = 'File '//trim(adjustl(File_name))//' could not be opened, the program terminates'
      call Save_error_details(Err, 2, Error_descript)
      print*, trim(adjustl(Error_descript))
      goto 3411
   endif
   
   if (.not.allocated(Scell)) allocate(Scell(1)) ! just for start, 1 supercell
   
   ! Read all lines in the file one by one:
   count_lines = 0
   do
      count_lines = count_lines + 1
      read(FN,'(a)',IOSTAT=Reason) read_line
      if (Reason < 0) then ! end of file
         exit
      elseif (Reason > 0) then ! couldn't read the line
         write(Error_descript,'(a,i5,a)') 'Could not read line ', count_lines, ' in file '//trim(adjustl(File_name))
         call Save_error_details(Err, 3, Error_descript)
         print*, trim(adjustl(Error_descript))
         exit
      else ! normal line, interprete it:
         call interpret_input_line(matter, numpar, laser, Scell, trim(adjustl(read_line)), FN, count_lines)
      endif
   enddo
3411 continue
   if (file_opened) close(FN)

   ! Check if FEL pulses are Gaussians, convert from FWHM into Gaussian sigma parameter:
   do i = 1, size(laser)
      if (laser(i)%KOP .EQ. 1) laser(i)%t = laser(i)%t/2.35482d0	! make a gaussian parameter out of it
   enddo
end subroutine read_input_txt



subroutine interpret_input_line(matter, numpar, laser, Scell, read_line, FN, count_lines)
   type(Solid), intent(inout) :: matter	! all material parameters
   type(Numerics_param), intent(inout) :: numpar 	! all numerical parameters
   type(Pulse), dimension(:), allocatable, intent(inout) :: laser	! Laser pulse parameters
   type(Super_cell), dimension(:), allocatable, intent(inout) :: Scell ! suoer-cell with all the atoms inside
   character(*), intent(in) :: read_line ! file read from the input file
   integer, intent(in) :: FN	! file number to read from
   integer, intent(inout) :: count_lines	! count on which line we are now
   !----------------------------------------------
   real(8) :: temp
   integer :: Reason, N, temp1, temp2, temp3
   character(200) :: read_next_line, Error_descript, temp_ch
   
   if (.not.allocated(Scell)) allocate(Scell(1)) ! So far we only use 1 supercell
   !---------------------------------------------------------------
   select case (read_line)
   !---------------------------------------------------------------
   case ('NAME', 'name', 'Name', 'MATERIAL', 'material', 'Material')
      read(FN,'(a)',IOSTAT=Reason) read_next_line
      count_lines = count_lines + 1
      if (Reason < 0) then ! end of file
         write(*,'(a)') 'Clould not complete action: end of input file after line: '//read_line
      elseif (Reason > 0) then ! couldn't read the line
         write(*,'(a,i5,a)') 'Could not read line ', count_lines, ' in file input file after line: '//read_line
      else
         matter%Name = trim(adjustl(read_next_line)) ! material name
      endif
   !---------------------------------------------------------------   
   case ('FORMULA', 'formula', 'Formula', 'CHEM', 'chem', 'Chem')
      read(FN,'(a)',IOSTAT=Reason) read_next_line
      count_lines = count_lines + 1
      if (Reason < 0) then ! end of file
         write(*,'(a)') 'Clould not complete action: end of input file after line: '//read_line
      elseif (Reason > 0) then ! couldn't read the line
         write(*,'(a,i5,a)') 'Could not read line ', count_lines, ' in file input file after line: '//read_line
      else
         matter%Chem = trim(adjustl(read_next_line)) ! chemical formula of the compound
      endif
   !---------------------------------------------------------------
   case ('TE', 'Te', 'te', 'Electrons_T')
      read(FN,'(a)',IOSTAT=Reason) read_next_line
      count_lines = count_lines + 1
      if (Reason < 0) then ! end of file
         write(*,'(a)') 'Clould not complete action: end of input file after line: '//read_line
      elseif (Reason > 0) then ! couldn't read the line
         write(*,'(a,i5,a)') 'Could not read line ', count_lines, ' in file input file after line: '//read_line
      else
         read(read_next_line,*, IOSTAT=Reason) Scell(1)%Te ! initial electron temperature [K]
         if (Reason /= 0) then
            write(*,'(a,i5,a)') 'Could not read Te from line ', count_lines, ' in file input file after line: '//read_line
            write(*,'(a)') 'Using default value instead...'
            Scell(1)%Te = 300.0d0 ! initial electron temperature [K]
         endif
         Scell(1)%TeeV = Scell(1)%Te/g_kb ! [eV] electron temperature
      endif
   !---------------------------------------------------------------
   case ('TA', 'Ta', 'ta', 'Atoms_T')
      read(FN,'(a)',IOSTAT=Reason) read_next_line
      count_lines = count_lines + 1
      if (Reason < 0) then ! end of file
         write(*,'(a)') 'Clould not complete action: end of input file after line: '//read_line
      elseif (Reason > 0) then ! couldn't read the line
         write(*,'(a,i5,a)') 'Could not read line ', count_lines, ' in file input file after line: '//read_line
      else
         read(read_next_line,*, IOSTAT=Reason) Scell(1)%Ta ! initial atomic temperature [K]
         if (Reason /= 0) then
            write(*,'(a,i5,a)') 'Could not read Ta from line ', count_lines, ' in file input file after line: '//read_line
            write(*,'(a)') 'Using default value instead...'
            Scell(1)%Ta = 300.0d0 ! initial electron temperature [K]
         endif
         Scell(1)%TaeV = Scell(1)%Ta/g_kb ! [eV] atomic temperature
      endif
   !---------------------------------------------------------------
   case ('TIME', 'Time', 'time', 'DURATION', 'Duration', 'duration', 't_total')
      read(FN,'(a)',IOSTAT=Reason) read_next_line
            count_lines = count_lines + 1
      if (Reason < 0) then ! end of file
         write(*,'(a)') 'Clould not complete action: end of input file after line: '//read_line
      elseif (Reason > 0) then ! couldn't read the line
         write(*,'(a,i5,a)') 'Could not read line ', count_lines, ' in file input file after line: '//read_line
      else
         read(read_next_line,'(e25.16)', IOSTAT=Reason) numpar%t_total ! total duration of simulation [fs]
         if (Reason /= 0) then
            write(*,'(a,i5,a)') 'Could not read DURATION from line ', count_lines, ' in file input file after line: '//read_line
            write(*,'(a)') 'Using default value instead...'
            numpar%t_total = 1000.0d0 ! [fs]
         endif
      endif
   !---------------------------------------------------------------
   case ('PULSES', 'Pulses', 'pulses', 'FEL')
      read(FN,'(a)',IOSTAT=Reason) read_next_line
      count_lines = count_lines + 1
      if (Reason < 0) then ! end of file
         write(*,'(a)') 'Clould not complete action: end of input file after line: '//read_line
      elseif (Reason > 0) then ! couldn't read the line
         write(*,'(a,i5,a)') 'Could not read line ', count_lines, ' in file input file after line: '//read_line
      else
         read(read_next_line,*, IOSTAT=Reason)  N ! How many pulses by default
         if (Reason /= 0) then
            write(*,'(a,i5,a)') 'Could not read NUMBER OF PULSES from line ', count_lines, ' in file input file after line: '//read_line
            write(*,'(a)') 'Using default value instead...'
         else
            call extend_laser(laser, N) ! see above
         endif
      endif
   !---------------------------------------------------------------
   case ('FLUENCE', 'Fluence', 'fluence', 'DOSE', 'Dose', 'dose')
      read(FN,'(a)',IOSTAT=Reason) read_next_line
      count_lines = count_lines + 1
      if (Reason < 0) then ! end of file
         write(*,'(a)') 'Clould not complete action: end of input file after line: '//read_line
      elseif (Reason > 0) then ! couldn't read the line
         write(*,'(a,i5,a)') 'Could not read line ', count_lines, ' in file input file after line: '//read_line
      else
         read(read_next_line,*, IOSTAT=Reason)  N, temp ! How many pulses by default
         if (Reason /= 0) then
            write(*,'(a,i5,a)') 'Could not read FLUENCE from line ', count_lines, ' in file input file after line: '//read_line
            write(*,'(a)') 'Using default value instead...'
         else
            ! if it's a new pulse, not mentioned before, first create an array element for it with default values:
            if (N > size(laser)) call extend_laser(laser, N-size(laser)) ! see above
            laser(N)%F = ABS(temp)  ! ABSORBED DOSE IN [eV/atom]
         endif
      endif
   !---------------------------------------------------------------
   case ('PHOTON_ENERGY', 'Photon_energy', 'photon_energy', 'photon', 'PHOTON', 'Photon', 'hw')
      read(FN,'(a)',IOSTAT=Reason) read_next_line
      count_lines = count_lines + 1
      if (Reason < 0) then ! end of file
         write(*,'(a)') 'Clould not complete action: end of input file after line: '//read_line
      elseif (Reason > 0) then ! couldn't read the line
         write(*,'(a,i5,a)') 'Could not read line ', count_lines, ' in file input file after line: '//read_line
      else
         read(read_next_line,*, IOSTAT=Reason)  N, temp ! How many pulses by default
         if (Reason /= 0) then
            write(*,'(a,i5,a)') 'Could not read PHOTON_ENERGY from line ', count_lines, ' in file input file after line: '//read_line
            write(*,'(a)') 'Using default value instead...'
         else
            ! if it's a new pulse, not mentioned before, first create an array element for it with default values:
            if (N > size(laser)) call extend_laser(laser, N-size(laser)) ! see above
            laser(N)%hw = ABS(temp)  ! PHOTON ENERGY IN [eV]
         endif
      endif
   !---------------------------------------------------------------
   case ('FWHM', 'PULSE_DURATION', 'Pulse_duration', 'pulse_duration')
      read(FN,'(a)',IOSTAT=Reason) read_next_line
      count_lines = count_lines + 1
      if (Reason < 0) then ! end of file
         write(*,'(a)') 'Clould not complete action: end of input file after line: '//read_line
      elseif (Reason > 0) then ! couldn't read the line
         write(*,'(a,i5,a)') 'Could not read line ', count_lines, ' in file input file after line: '//read_line
      else
         read(read_next_line,*, IOSTAT=Reason)  N, temp ! How many pulses by default
         if (Reason /= 0) then
            write(*,'(a,i5,a)') 'Could not read PULSE_DURATION from line ', count_lines, ' in file input file after line: '//read_line
            write(*,'(a)') 'Using default value instead...'
         else
            ! if it's a new pulse, not mentioned before, first create an array element for it with default values:
            if (N > size(laser)) call extend_laser(laser, N-size(laser)) ! see above
            laser(N)%t = temp	  ! PULSE FWHM-DURATION IN [fs]
         endif
      endif
   !---------------------------------------------------------------
   case ('PULSE_SHAPE', 'Pulse_shape', 'pulse_shape')
      read(FN,'(a)',IOSTAT=Reason) read_next_line
      count_lines = count_lines + 1
      if (Reason < 0) then ! end of file
         write(*,'(a)') 'Clould not complete action: end of input file after line: '//read_line
      elseif (Reason > 0) then ! couldn't read the line
         write(*,'(a,i5,a)') 'Could not read line ', count_lines, ' in file input file after line: '//read_line
      else
         read(read_next_line,*, IOSTAT=Reason)  N, temp_ch
         if (Reason /= 0) then
            write(*,'(a,i5,a)') 'Could not read PULSE_SHAPE from line ', count_lines, ' in file input file after line: '//read_line
            write(*,'(a)') 'Using default value instead...'
         else
            ! if it's a new pulse, not mentioned before, first create an array element for it with default values:
            if (N > size(laser)) call extend_laser(laser, N-size(laser)) ! see above
            
            selectcase (trim(adjustl(temp_ch)))
            case ('0', 'FLAT_TOP', 'Flat_top', 'flat_top')
               laser(N)%KOP = 0  	  ! type of pulse: 0=rectangular, 1=Gaussian, 2=SASE
            case ('2', 'SASE', 'sase', 'Sase')
               laser(N)%KOP = 2  	  ! type of pulse: 0=rectangular, 1=Gaussian, 2=SASE
            case default
               laser(N)%KOP = 1  	  ! type of pulse: 0=rectangular, 1=Gaussian, 2=SASE
               laser(N)%t = laser(N)%t/2.35482	! make a gaussian parameter out of it
            endselect
         endif
      endif
   !---------------------------------------------------------------
   case ('PULSE_CENTER', 'Pulse_center', 'pulse_center', 'pulse_position')
      read(FN,'(a)',IOSTAT=Reason) read_next_line
      count_lines = count_lines + 1
      if (Reason < 0) then ! end of file
         write(*,'(a)') 'Clould not complete action: end of input file after line: '//read_line
      elseif (Reason > 0) then ! couldn't read the line
         write(*,'(a,i5,a)') 'Could not read line ', count_lines, ' in file input file after line: '//read_line
      else
         read(read_next_line,*, IOSTAT=Reason)  N, temp ! How many pulses by default
         if (Reason /= 0) then
            write(*,'(a,i5,a)') 'Could not read PULSE_CENTER from line ', count_lines, ' in file input file after line: '//read_line
            write(*,'(a)') 'Using default value instead...'
         else
            ! if it's a new pulse, not mentioned before, first create an array element for it with default values:
            if (N > size(laser)) call extend_laser(laser, N-size(laser)) ! see above
            laser(N)%t0 = temp	  ! POSITION OF THE MAXIMUM OF THE PULSE IN [fs]
         endif
      endif
   !---------------------------------------------------------------
   case ('OPTICAL', 'Optical', 'optical')
      read(FN,'(a)',IOSTAT=Reason) read_next_line
      count_lines = count_lines + 1
      if (Reason < 0) then ! end of file
         write(*,'(a)') 'Clould not complete action: end of input file after line: '//read_line
      elseif (Reason > 0) then ! couldn't read the line
         write(*,'(a,i5,a)') 'Could not read line ', count_lines, ' in file input file after line: '//read_line
      else
         select case (trim(adjustl(read_next_line)))
         case ('T', 't', 'TRUE', 'True', 'true', '.true.', '1')
            numpar%do_drude = .true.	! included optical calculations
         case default
            numpar%optic_model = 0 ! no optical calculations by default
            numpar%do_drude = .false.	! excluded optical calculations
         endselect
      endif
   !---------------------------------------------------------------
   case ('OPTIC_MODEL', 'Optic_model', 'optic_model', 'optical_model', 'OPTICAL_MODEL')
      read(FN,'(a)',IOSTAT=Reason) read_next_line
      count_lines = count_lines + 1   
      if (Reason < 0) then ! end of file
         write(*,'(a)') 'Clould not complete action: end of input file after line: '//read_line
      elseif (Reason > 0) then ! couldn't read the line
         write(*,'(a,i5,a)') 'Could not read line ', count_lines, ' in file input file after line: '//read_line
      else
         select case (trim(adjustl(read_next_line))) ! optical coefficients: 0=no, 1=Drude, 2=Trani-k, 3=Trani gamma
         case ('1', 'DRUDE', 'Drude', 'drude')
            numpar%optic_model = 1 ! no optical calculations by default
            numpar%do_drude = .true.	! included optical calculations
         case ('2', 'TRANI-K', 'Trani-k', 'trani-k', 'TREANI_K', 'Trani_k', 'trani_k')
            numpar%optic_model = 2 ! no optical calculations by default
            numpar%do_drude = .true.	! included optical calculations
         case ('3', 'TRANI', 'Trani', 'trani', 'TRANI_GAMMA', 'Trani_gamma', 'trani_gamma')
            numpar%optic_model = 3 ! no optical calculations by default
            numpar%do_drude = .true.	! included optical calculations
         case default
            numpar%optic_model = 0 ! no optical calculations by default
            numpar%do_drude = .false.	! excluded optical calculations
         endselect
      endif
   !---------------------------------------------------------------
   case ('RAYS', 'Rays', 'rays')
      read(FN,'(a)',IOSTAT=Reason) read_next_line
      count_lines = count_lines + 1   
      if (Reason < 0) then ! end of file
         write(*,'(a)') 'Clould not complete action: end of input file after line: '//read_line
      elseif (Reason > 0) then ! couldn't read the line
         write(*,'(a,i5,a)') 'Could not read line ', count_lines, ' in file input file after line: '//read_line
      else
         select case (trim(adjustl(read_next_line))) ! Absorbtion of how many rays (0=exclude, 1=1st ray, 2=sum all)
         case ('1', 'ONE', 'One', 'one', 'SINGLE', 'Single', 'single')
            numpar%drude_ray = 1 ! no optical calculations by default
            numpar%do_drude = .true.	! included optical calculations
         case ('2', 'ALL', 'All', 'all', 'SUM', 'Sum', 'sum')
            numpar%drude_ray = 2 ! no optical calculations by default
            numpar%do_drude = .true.	! included optical calculations
         case default
            numpar%drude_ray = 0
            numpar%do_drude = .false.	! excluded optical calculations
         endselect
      endif
   !---------------------------------------------------------------
   case ('PROBE_SPECTRUM', 'Probe_spectrum', 'probe_spectrum')
      read(FN,'(a)',IOSTAT=Reason) read_next_line
      count_lines = count_lines + 1   
      if (Reason < 0) then ! end of file
         write(*,'(a)') 'Clould not complete action: end of input file after line: '//read_line
      elseif (Reason > 0) then ! couldn't read the line
         write(*,'(a,i5,a)') 'Could not read line ', count_lines, ' in file input file after line: '//read_line
      else
         read(read_next_line,*, IOSTAT=Reason) Scell(1)%eps%E_min, Scell(1)%eps%E_max, Scell(1)%eps%dE
         if (Reason /= 0) then
            write(*,'(a,i5,a)') 'Could not read PROBE_SPECTRUM parameters from line ', count_lines, ' in file input file after line: '//read_line
            write(*,'(a)') 'Using default values instead...'
            Scell(1)%eps%E_min = 0.05d0 ! starting point of the grid of energy [eV]
            Scell(1)%eps%E_max = 50.0d0 ! ending point of the grid of energy [eV]
            Scell(1)%eps%dE = 0.1d0    ! grid step of energy [eV]
         endif
      endif
   !---------------------------------------------------------------
   case ('PROBE', 'Probe', 'probe', 'probe_wavelength')
      read(FN,'(a)',IOSTAT=Reason) read_next_line
      count_lines = count_lines + 1   
      if (Reason < 0) then ! end of file
         write(*,'(a)') 'Clould not complete action: end of input file after line: '//read_line
      elseif (Reason > 0) then ! couldn't read the line
         write(*,'(a,i5,a)') 'Could not read line ', count_lines, ' in file input file after line: '//read_line
      else
         read(read_next_line,*, IOSTAT=Reason) Scell(1)%eps%l ! probe-pulse wavelength [nm]
         if (Reason /= 0) then
            write(*,'(a,i5,a)') 'Could not read PROBE wavelength from line ', count_lines, ' in file input file after line: '//read_line
            write(*,'(a)') 'Using default values instead...'
            Scell(1)%eps%l = 800.0d0	! probe-pulse wavelength [nm]
         endif
         Scell(1)%eps%w = 2.0d0*g_Pi*g_cvel/(Scell(1)%eps%l*1d-9) ! [1/sec] frequency
      endif
   !---------------------------------------------------------------
   case ('PROBE_DURATION', 'Probe_duration', 'probe_duration', 'probe_tau', 'PROBE_TAU', 'Probe_tau')
      read(FN,'(a)',IOSTAT=Reason) read_next_line
      count_lines = count_lines + 1   
      if (Reason < 0) then ! end of file
         write(*,'(a)') 'Clould not complete action: end of input file after line: '//read_line
      elseif (Reason > 0) then ! couldn't read the line
         write(*,'(a,i5,a)') 'Could not read line ', count_lines, ' in file input file after line: '//read_line
      else
         read(read_next_line,*, IOSTAT=Reason) Scell(1)%eps%tau ! probe duration FWHM [fs]
         if (Reason /= 0) then
            write(*,'(a,i5,a)') 'Could not read PROBE_DURATION from line ', count_lines, ' in file input file after line: '//read_line
            write(*,'(a)') 'Using default values instead...'
            Scell(1)%eps%tau = -10.0d0	! probe duration FWHM [fs]
         endif
      endif
   !---------------------------------------------------------------
   case ('PROBE_ANGLE', 'Probe_angle', 'probe_angle', 'probe_theta')
      read(FN,'(a)',IOSTAT=Reason) read_next_line
      count_lines = count_lines + 1   
      if (Reason < 0) then ! end of file
         write(*,'(a)') 'Clould not complete action: end of input file after line: '//read_line
      elseif (Reason > 0) then ! couldn't read the line
         write(*,'(a,i5,a)') 'Could not read line ', count_lines, ' in file input file after line: '//read_line
      else
         read(read_next_line,*, IOSTAT=Reason) Scell(1)%eps%teta ! Angle of prob-pulse with respect to normal [degrees]
         if (Reason /= 0) then
            write(*,'(a,i5,a)') 'Could not read PROBE_ANGLE from line ', count_lines, ' in file input file after line: '//read_line
            write(*,'(a)') 'Using default values instead...'
            Scell(1)%eps%teta = 0.0d0	! Angle of prob-pulse with respect to normal [degrees]
         endif
         Scell(1)%eps%teta = Scell(1)%eps%teta*g_Pi/(180.0d0) !c [radians]
      endif
   !---------------------------------------------------------------
   case ('THICKNESS', 'Thickness', 'thickness', 'LAYER', 'Layer', 'layer')
      read(FN,'(a)',IOSTAT=Reason) read_next_line
      count_lines = count_lines + 1   
      if (Reason < 0) then ! end of file
         write(*,'(a)') 'Clould not complete action: end of input file after line: '//read_line
      elseif (Reason > 0) then ! couldn't read the line
         write(*,'(a,i5,a)') 'Could not read line ', count_lines, ' in file input file after line: '//read_line
      else
         read(read_next_line,*, IOSTAT=Reason) Scell(1)%eps%dd	! material thickness [nm]
         if (Reason /= 0) then
            write(*,'(a,i5,a)') 'Could not read LAYER THICKNESS from line ', count_lines, ' in file input file after line: '//read_line
            write(*,'(a)') 'Using default values instead...'
            Scell(1)%eps%dd = 100.0d0	! material thickness [nm]
         endif
      endif
   !---------------------------------------------------------------
   case ('SUPERCELL', 'Supercell', 'supercell')
      read(FN,'(a)',IOSTAT=Reason) read_next_line
      count_lines = count_lines + 1   
      if (Reason < 0) then ! end of file
         write(*,'(a)') 'Clould not complete action: end of input file after line: '//read_line
      elseif (Reason > 0) then ! couldn't read the line
         write(*,'(a,i5,a)') 'Could not read line ', count_lines, ' in file input file after line: '//read_line
      else
         read(read_next_line,*, IOSTAT=Reason) matter%cell_x, matter%cell_y, matter%cell_z ! number of unit-cells in X,Y,Z
         if (Reason /= 0) then
            write(*,'(a,i5,a)') 'Could not read SUPERCELL from line ', count_lines, ' in file input file after line: '//read_line
            write(*,'(a)') 'Using default values instead...'
             matter%cell_x = 1
             matter%cell_y = 1
             matter%cell_z = 1
         endif
      endif
   !---------------------------------------------------------------
   case ('PERIODIC', 'Periodic', 'periodic')
      read(FN,'(a)',IOSTAT=Reason) read_next_line
      count_lines = count_lines + 1   
      if (Reason < 0) then ! end of file
         write(*,'(a)') 'Clould not complete action: end of input file after line: '//read_line
      elseif (Reason > 0) then ! couldn't read the line
         write(*,'(a,i5,a)') 'Could not read line ', count_lines, ' in file input file after line: '//read_line
      else
         read(read_next_line,*, IOSTAT=Reason) temp1, temp2, temp3	! periodic or not
         if (Reason /= 0) then
            write(*,'(a,i5,a)') 'Could not read PERIODIC from line ', count_lines, ' in file input file after line: '//read_line
            write(*,'(a)') 'Using default values instead...'
            numpar%r_periodic(:) = .true.
         else
            if (temp1 == 1) then
               numpar%r_periodic(1) = .true.
            else
               numpar%r_periodic(1) = .false.
            endif
            if (temp2 == 1) then
               numpar%r_periodic(2) = .true.
            else
               numpar%r_periodic(2) = .false.
            endif
            if (temp3 == 1) then
               numpar%r_periodic(3) = .true.
            else
               numpar%r_periodic(3) = .false.
            endif
         endif
      endif
   !---------------------------------------------------------------
   case ('ATOMIC_DATA', 'Atomic_data', 'atomic_data')
      read(FN,'(a)',IOSTAT=Reason) read_next_line
      count_lines = count_lines + 1   
      if (Reason < 0) then ! end of file
         write(*,'(a)') 'Clould not complete action: end of input file after line: '//read_line
      elseif (Reason > 0) then ! couldn't read the line
         write(*,'(a,i5,a)') 'Could not read line ', count_lines, ' in file input file after line: '//read_line
      else
         selectcase (trim(adjustl(read_next_line)))
         case ('CDF', 'cdf', 'Cdf')
            numpar%At_base = 'CDF' ! where to take atomic data from (EADL, CDF, XATOM...)
         case ('eald', 'EADL', 'Eadl', 'BEB', 'Beb', 'beb')
            numpar%At_base = 'EADL' ! where to take atomic data from (EADL, CDF, XATOM...)
         case default
            write(*,'(a,i5,a)') 'Could not interpret ATOMIC_DATA from line ', count_lines, ' in file input file after line: '//read_line
            write(*,'(a)') 'Using default values instead...'
            numpar%At_base = 'EADL' ! where to take atomic data from (EADL, CDF, XATOM...)
         endselect
      endif
   !---------------------------------------------------------------
   case ('DENSITY', 'Density', 'density', 'MC_Density')
      read(FN,'(a)',IOSTAT=Reason) read_next_line
      count_lines = count_lines + 1   
      if (Reason < 0) then ! end of file
         write(*,'(a)') 'Clould not complete action: end of input file after line: '//read_line
      elseif (Reason > 0) then ! couldn't read the line
         write(*,'(a,i5,a)') 'Could not read line ', count_lines, ' in file input file after line: '//read_line
      else
         read(read_next_line,*, IOSTAT=Reason) matter%dens
         if (Reason /= 0) then
            write(*,'(a,i5,a)') 'Could not read MC_DENSITY from line ', count_lines, ' in file input file after line: '//read_line
            write(*,'(a)') 'Using default values instead...'
            matter%dens = -1.0d0 ! [g/cm^3] density of the material (negative = use MD supercell to evaluate it)
         endif
      endif
   !---------------------------------------------------------------
   case ('MC_ITERATIONS', 'MC_iterations', 'ITERATIONS', 'Iterations', 'interations')
      read(FN,'(a)',IOSTAT=Reason) read_next_line
      count_lines = count_lines + 1   
      if (Reason < 0) then ! end of file
         write(*,'(a)') 'Clould not complete action: end of input file after line: '//read_line
      elseif (Reason > 0) then ! couldn't read the line
         write(*,'(a,i5,a)') 'Could not read line ', count_lines, ' in file input file after line: '//read_line
      else
         read(read_next_line,*, IOSTAT=Reason) numpar%NMC
         if (Reason /= 0) then
            write(*,'(a,i5,a)') 'Could not read MC_ITERATIONS from line ', count_lines, ' in file input file after line: '//read_line
            write(*,'(a)') 'Using default values instead...'
            numpar%NMC = 30000	! number of iterations in the MC module
         endif
      endif
   !---------------------------------------------------------------
   case ('NO_ELASTIC_MC', 'No_elastic_MC', 'NO_ELASTIC', 'no_elastic_mc', 'no_elastic', 'MC_NO_ELASTIC', 'MC_no_elastic')      
      numpar%do_elastic_MC = .false.	! don't allow elastic scattering of electrons on atoms within MC module
   !---------------------------------------------------------------
   case ('THREADS', 'Threads', 'threads', 'Openmp', 'OpenMP', 'OMP', 'OMP_threads', 'OMP_THREADS')
      read(FN,'(a)',IOSTAT=Reason) read_next_line
      count_lines = count_lines + 1   
      if (Reason < 0) then ! end of file
         write(*,'(a)') 'Clould not complete action: end of input file after line: '//read_line
      elseif (Reason > 0) then ! couldn't read the line
         write(*,'(a,i5,a)') 'Could not read line ', count_lines, ' in file input file after line: '//read_line
      else
         read(read_next_line,*, IOSTAT=Reason) numpar%NOMP
         if (Reason /= 0) then
            write(*,'(a,i5,a)') 'Could not read OMP_threads from line ', count_lines, ' in file input file after line: '//read_line
            write(*,'(a)') 'Using default values instead...'
#ifdef OMP_inside
            numpar%NOMP = omp_get_max_threads()	! number of processors available by default
#else ! if you set to use OpenMP in compiling: 'make OMP=no'
            numpar%NOMP = 1	! unparallelized by default
#endif
         endif
      endif
   !---------------------------------------------------------------
   case ('FROZEN', 'Frozen', 'frozen', 'FROZEN_ATOMS', 'Frozen_atoms', 'frozen_atoms')
      numpar%do_atoms = .false.	! Atoms are NOT allowed to move
   !---------------------------------------------------------------
   case ('W_PR', 'Parrinello_Rahman_MASS', 'SUPERCELL_MASS', 'Supercell_mass', 'supercell_mass')
      read(FN,'(a)',IOSTAT=Reason) read_next_line
      count_lines = count_lines + 1   
      if (Reason < 0) then ! end of file
         write(*,'(a)') 'Clould not complete action: end of input file after line: '//read_line
      elseif (Reason > 0) then ! couldn't read the line
         write(*,'(a,i5,a)') 'Could not read line ', count_lines, ' in file input file after line: '//read_line
      else
         read(read_next_line,*, IOSTAT=Reason) matter%W_PR
         if (Reason /= 0) then
            write(*,'(a,i5,a)') 'Could not read Parinello_Rahman_MASS from line ', count_lines, ' in file input file after line: '//read_line
            write(*,'(a)') 'Using default values instead...'
            matter%W_PR = 25.5d0  ! Parinello-Rahman super-vell mass coefficient
         endif
      endif
   !---------------------------------------------------------------
   case ('dt', 'DT', 'Dt', 'MD_dt', 'MD_DT', 'MD_timestep', 'MD_TIMESTEP', 'TIME_STEP', 'Time_step', 'time_step', 'timestep', 'Timestep', 'TIMESTEP')
      read(FN,'(a)',IOSTAT=Reason) read_next_line
      count_lines = count_lines + 1   
      if (Reason < 0) then ! end of file
         write(*,'(a)') 'Clould not complete action: end of input file after line: '//read_line
      elseif (Reason > 0) then ! couldn't read the line
         write(*,'(a,i5,a)') 'Could not read line ', count_lines, ' in file input file after line: '//read_line
      else
         read(read_next_line,*, IOSTAT=Reason) numpar%dt
         if (Reason /= 0) then
            write(*,'(a,i5,a)') 'Could not read MD_TIMESTEP from line ', count_lines, ' in file input file after line: '//read_line
            write(*,'(a)') 'Using default values instead...'
            numpar%dt = 0.01d0 	! Time step for MD [fs]
         endif
         numpar%halfdt = numpar%dt/2.0d0            ! dt/2, often used
         numpar%dtsqare = numpar%dt*numpar%halfdt   ! dt*dt/2, often used
         numpar%dt3 = numpar%dt**3/6.0d0            ! dt^3/6, often used
         numpar%dt4 = numpar%dt*numpar%dt3/8.0d0    ! dt^4/48, often used
      endif
   !---------------------------------------------------------------
   case ('Save_dt', 'SAVE_DT', 'Save_Dt', 'SAVE', 'Save', 'save')
      read(FN,'(a)',IOSTAT=Reason) read_next_line
      count_lines = count_lines + 1   
      if (Reason < 0) then ! end of file
         write(*,'(a)') 'Clould not complete action: end of input file after line: '//read_line
      elseif (Reason > 0) then ! couldn't read the line
         write(*,'(a,i5,a)') 'Could not read line ', count_lines, ' in file input file after line: '//read_line
      else
         read(read_next_line,*, IOSTAT=Reason) numpar%dt_save
         if (Reason /= 0) then
            write(*,'(a,i5,a)') 'Could not read SAVE_DT from line ', count_lines, ' in file input file after line: '//read_line
            write(*,'(a)') 'Using default values instead...'
            numpar%dt_save = 1.0d0	! save data into files every [fs]
         endif
      endif
   !---------------------------------------------------------------
   case ('Const_P', 'CONST_P', 'NPH', 'CONSTANT_P', 'Constant_P', 'Constant_pressure')
      numpar%p_const = .true.	! P=const
   !---------------------------------------------------------------
   case ('Const_V', 'CONST_V', 'NVE', 'CONSTANT_V', 'Constant_V', 'Constant_volume')
      numpar%p_const = .false.	! V=const
   !---------------------------------------------------------------
   case ('Pressure', 'PRESSURE', 'pressure')
      read(FN,'(a)',IOSTAT=Reason) read_next_line
      count_lines = count_lines + 1   
      if (Reason < 0) then ! end of file
         write(*,'(a)') 'Clould not complete action: end of input file after line: '//read_line
      elseif (Reason > 0) then ! couldn't read the line
         write(*,'(a,i5,a)') 'Could not read line ', count_lines, ' in file input file after line: '//read_line
      else
         read(read_next_line,*, IOSTAT=Reason) matter%p_ext
         if (Reason /= 0) then
            write(*,'(a,i5,a)') 'Could not read PRESSURE from line ', count_lines, ' in file input file after line: '//read_line
            write(*,'(a)') 'Using atmospheric pressure instead...'
            matter%p_ext = g_P_atm	! External pressure [Pa] (0 = normal atmospheric pressure)
         else
            numpar%p_const = .true.	! P=const
         endif
      endif
   !---------------------------------------------------------------
   case ('SCHEME', 'Scheme', 'scheme')
      read(FN,'(a)',IOSTAT=Reason) read_next_line
      count_lines = count_lines + 1   
      if (Reason < 0) then ! end of file
         write(*,'(a)') 'Clould not complete action: end of input file after line: '//read_line
      elseif (Reason > 0) then ! couldn't read the line
         write(*,'(a,i5,a)') 'Could not read line ', count_lines, ' in file input file after line: '//read_line
      else
         read(read_next_line,*, IOSTAT=Reason) N
         if (Reason /= 0) then
            write(*,'(a,i5,a)') 'Could not read EL_ION_SCHEME from line ', count_lines, ' in file input file after line: '//read_line
            write(*,'(a)') 'Using default values instead...'
            numpar%el_ion_scheme = 0	! scheme (0=decoupled electrons; 1=enforced energy conservation; 2=T=const; 3=BO)
         else
            selectcase(N)
            case (1:3)
               numpar%el_ion_scheme = N	! scheme (0=decoupled electrons; 1=enforced energy conservation; 2=T=const; 3=BO)
            case default
               numpar%el_ion_scheme = 0	! scheme (0=decoupled electrons; 1=enforced energy conservation; 2=T=const; 3=BO)
            endselect
         endif
      endif
   !---------------------------------------------------------------
   case ('NVE_STARTS', 'START_NVE', 'Start_NVE', 'NVE_starts')
      read(FN,'(a)',IOSTAT=Reason) read_next_line
      count_lines = count_lines + 1   
      if (Reason < 0) then ! end of file
         write(*,'(a)') 'Clould not complete action: end of input file after line: '//read_line
      elseif (Reason > 0) then ! couldn't read the line
         write(*,'(a,i5,a)') 'Could not read line ', count_lines, ' in file input file after line: '//read_line
      else
         read(read_next_line,*, IOSTAT=Reason) numpar%t_Te_Ee ! time when we switch from Te=const, to Ee=const [fs] 
         if (Reason /= 0) then
            write(*,'(a,i5,a)') 'Could not read START_NVE from line ', count_lines, ' in file input file after line: '//read_line
            write(*,'(a)') 'Using default values instead...'
            numpar%t_Te_Ee = 1.0d-3	! time when we switch from Te=const, to Ee=const [fs] 
         endif
      endif
   !---------------------------------------------------------------
   case ('COUPLING_MODEL', 'Coupling_model', 'COUPLING', 'Coupling', 'coupling')
      read(FN,'(a)',IOSTAT=Reason) read_next_line
      count_lines = count_lines + 1   
      if (Reason < 0) then ! end of file
         write(*,'(a)') 'Clould not complete action: end of input file after line: '//read_line
      elseif (Reason > 0) then ! couldn't read the line
         write(*,'(a,i5,a)') 'Could not read line ', count_lines, ' in file input file after line: '//read_line
      else
         selectcase (trim(adjustl(read_next_line)))
         case ('0', 'NO', 'No', 'Exclude', 'EXCLUDE', 'exclude')
            numpar%NA_kind = 0	! 0=no coupling, 1=dynamical coupling (2=Fermi-golden_rule)
            numpar%Nonadiabat = .false.  ! included
         case ('2', 'FGR', 'Fermi', 'FERMI', 'FERMI_GOLDEN_RULE')
            numpar%NA_kind = 2	! 0=no coupling, 1=dynamical coupling (2=Fermi-golden_rule)
            numpar%Nonadiabat = .true.  ! included
         case default
            numpar%NA_kind = 1	! 0=no coupling, 1=dynamical coupling (2=Fermi-golden_rule)
            numpar%Nonadiabat = .true.  ! included
         endselect
      endif
   !---------------------------------------------------------------
   case ('COUPLING_INCLUDE', 'INCLUDE_COUPLING')
      read(FN,'(a)',IOSTAT=Reason) read_next_line
      count_lines = count_lines + 1   
      if (Reason < 0) then ! end of file
         write(*,'(a)') 'Clould not complete action: end of input file after line: '//read_line
      elseif (Reason > 0) then ! couldn't read the line
         write(*,'(a,i5,a)') 'Could not read line ', count_lines, ' in file input file after line: '//read_line
      else
         selectcase (trim(adjustl(read_next_line)))
         case ('0', 'NO', 'No', 'Exclude', 'EXCLUDE', 'exclude')
            numpar%NA_kind = 0	! 0=no coupling, 1=dynamical coupling (2=Fermi-golden_rule)
         case ('2', 'FGR', 'Fermi', 'FERMI', 'FERMI_GOLDEN_RULE')
            numpar%NA_kind = 2	! 0=no coupling, 1=dynamical coupling (2=Fermi-golden_rule)
         case default
            numpar%NA_kind = 1	! 0=no coupling, 1=dynamical coupling (2=Fermi-golden_rule)
         endselect
      endif
   !---------------------------------------------------------------
   case ('COUPLING_STARTS', 'START_COUPLING', 'Start_coupling', 'Coupling_starts')
      read(FN,'(a)',IOSTAT=Reason) read_next_line
      count_lines = count_lines + 1   
      if (Reason < 0) then ! end of file
         write(*,'(a)') 'Clould not complete action: end of input file after line: '//read_line
      elseif (Reason > 0) then ! couldn't read the line
         write(*,'(a,i5,a)') 'Could not read line ', count_lines, ' in file input file after line: '//read_line
      else
         read(read_next_line,*, IOSTAT=Reason) numpar%t_NA
         if (Reason /= 0) then
            write(*,'(a,i5,a)') 'Could not read START_COUPLING from line ', count_lines, ' in file input file after line: '//read_line
            write(*,'(a)') 'Using default values instead...'
            numpar%t_NA = 1.0d-3	! [fs] start of the nonadiabatic coupling
         endif
      endif
   !---------------------------------------------------------------
   case ('WINDOW', 'Window', 'window', 'ACCEPTANCE', 'Acceptance', 'acceptance')
      read(FN,'(a)',IOSTAT=Reason) read_next_line
      count_lines = count_lines + 1   
      if (Reason < 0) then ! end of file
         write(*,'(a)') 'Clould not complete action: end of input file after line: '//read_line
      elseif (Reason > 0) then ! couldn't read the line
         write(*,'(a,i5,a)') 'Could not read line ', count_lines, ' in file input file after line: '//read_line
      else
         read(read_next_line,*, IOSTAT=Reason) numpar%acc_window
         if (Reason /= 0) then
            write(*,'(a,i5,a)') 'Could not read ACCEPTANCE_WINDOW from line ', count_lines, ' in file input file after line: '//read_line
            write(*,'(a)') 'Using default values instead...'
            numpar%acc_window = 5.0d0	! [eV] acceptance window for nonadiabatic coupling:
         endif
      endif   
   !---------------------------------------------------------------
   case ('QUENCHING', 'Quenching', 'quenching')
      read(FN,'(a)',IOSTAT=Reason) read_next_line
      count_lines = count_lines + 1   
      if (Reason < 0) then ! end of file
         write(*,'(a)') 'Clould not complete action: end of input file after line: '//read_line
      elseif (Reason > 0) then ! couldn't read the line
         write(*,'(a,i5,a)') 'Could not read line ', count_lines, ' in file input file after line: '//read_line
      else
         read(read_next_line,*, IOSTAT=Reason) numpar%at_cool_start, numpar%at_cool_dt ! starting from when [fs] and how often [fs]
         if (Reason /= 0) then
            write(*,'(a,i5,a)') 'Could not read QUENCHING parameteres from line ', count_lines, ' in file input file after line: '//read_line
            write(*,'(a)') 'Using default values instead...'
            numpar%at_cool_start = 2500.0	! starting from when [fs]
            numpar%at_cool_dt = 40.0	! how often [fs]
            numpar%do_cool = .false.	! quenching excluded 
         else
            numpar%do_cool = .true.	! quenching included 
         endif
      endif
   !---------------------------------------------------------------
   case ('TRANSPORT', 'Transport', 'transport')
   read(FN,'(a)',IOSTAT=Reason) read_next_line
      count_lines = count_lines + 1   
      if (Reason < 0) then ! end of file
         write(*,'(a)') 'Clould not complete action: end of input file after line: '//read_line
      elseif (Reason > 0) then ! couldn't read the line
         write(*,'(a,i5,a)') 'Could not read line ', count_lines, ' in file input file after line: '//read_line
      else
         read(read_next_line,*, IOSTAT=Reason) matter%T_bath, matter%tau_bath ! [K] bath temperature? [fs] time constant of cooling
         if (Reason /= 0) then
            write(*,'(a,i5,a)') 'Could not read TRANSPORT parameteres from line ', count_lines, ' in file input file after line: '//read_line
            write(*,'(a)') 'Using default values instead...'
            matter%T_bath = 300.0d0	! [K] bath temperature
            matter%T_bath = matter%T_bath/g_kb	! [eV] thermostat temperature
            matter%tau_bath = 300.0d0	! [fs] time constant of cooling
            numpar%Transport = .false. ! excluded heat transport
         else
            numpar%Transport = .true. ! excluded heat transport
            matter%T_bath = matter%T_bath/g_kb	! [eV] thermostat temperature
         endif
      endif
   !---------------------------------------------------------------
   case ('CUT_OFF', 'Cut_off', 'cut_off')
   read(FN,'(a)',IOSTAT=Reason) read_next_line
      count_lines = count_lines + 1   
      if (Reason < 0) then ! end of file
         write(*,'(a)') 'Clould not complete action: end of input file after line: '//read_line
      elseif (Reason > 0) then ! couldn't read the line
         write(*,'(a,i5,a)') 'Could not read line ', count_lines, ' in file input file after line: '//read_line
      else
         selectcase (trim(adjustl(read_next_line)))
         case ('DYNAMIC', 'Dynamic', 'dynamic', 'DYNAMICAL', 'Dynamical', 'dynamical')
            numpar%E_cut = -10.0d0 ! [eV] cut-off energy for high
            numpar%E_cut_dynamic = .true. ! do not change E_cut
         case default
            read(read_next_line,*, IOSTAT=Reason) numpar%E_cut ! [K] bath temperature? [fs] time constant of cooling
            if (Reason /= 0) then
               write(*,'(a,i5,a)') 'Could not read MC CUT_OFF parameteres from line ', count_lines, ' in file input file after line: '//read_line
               write(*,'(a)') 'Using default values instead...'
               numpar%E_cut = 10.0d0 ! [eV] cut-off energy for high
               numpar%E_cut_dynamic = .false. ! do not change E_cut
            else
               if (numpar%E_cut <= 0.0d0 ) numpar%E_cut_dynamic = .true. ! E_cut = upper bound of TB energy levels of the CB
            endif
         endselect
      endif
   !---------------------------------------------------------------
   case ('WORK_FUNCTION', 'Work_function', 'work_function')
      read(FN,'(a)',IOSTAT=Reason) read_next_line
      count_lines = count_lines + 1   
      if (Reason < 0) then ! end of file
         write(*,'(a)') 'Clould not complete action: end of input file after line: '//read_line
      elseif (Reason > 0) then ! couldn't read the line
         write(*,'(a,i5,a)') 'Could not read line ', count_lines, ' in file input file after line: '//read_line
      else
         read(read_next_line,*, IOSTAT=Reason) numpar%E_work ! [K] bath temperature? [fs] time constant of cooling
         if (Reason /= 0) then
            write(*,'(a,i5,a)') 'Could not read WORK FUNCTION parameteres from line ', count_lines, ' in file input file after line: '//read_line
            write(*,'(a)') 'Using default values instead...'
            numpar%E_work = 1.0d30 ! [eV] work function (exclude electron emission)
         endif
      endif
   !---------------------------------------------------------------
   case ('EMISSION_COLLISIONS', 'Emission_collisions', 'emission_collisions')
      read(FN,'(a)',IOSTAT=Reason) read_next_line
      count_lines = count_lines + 1   
      if (Reason < 0) then ! end of file
         write(*,'(a)') 'Clould not complete action: end of input file after line: '//read_line
      elseif (Reason > 0) then ! couldn't read the line
         write(*,'(a,i5,a)') 'Could not read line ', count_lines, ' in file input file after line: '//read_line
      else
         read(read_next_line,*, IOSTAT=Reason) numpar%E_work ! [K] bath temperature? [fs] time constant of cooling
         if (Reason /= 0) then
            write(*,'(a,i5,a)') 'Could not read EMISSION_COLLISIONS parameteres from line ', count_lines, ' in file input file after line: '//read_line
            write(*,'(a)') 'Using NO EMISSION instead...'
            numpar%E_work = 1.0d30 ! [eV] work function (exclude electron emission)
         else
            numpar%E_work = -numpar%E_work
         endif
      endif   
   !---------------------------------------------------------------
   case ('PRINT_Ei', 'Print_Ei', 'print_Ei', 'print_energy_levels')
      numpar%save_Ei = .true.	! included printout energy levels (band structure)
   !---------------------------------------------------------------
   case ('PRINT_DOS', 'Print_DOS', 'print_DOS', 'print_dos')
      numpar%save_DOS = .true.	! included printout of DOS
   !---------------------------------------------------------------
   case ('SMEARING_DOS', 'Smearing_DOS', 'smearing_DOS', 'smearing_dos')
      read(FN,'(a)',IOSTAT=Reason) read_next_line
      count_lines = count_lines + 1   
      if (Reason < 0) then ! end of file
         write(*,'(a)') 'Clould not complete action: end of input file after line: '//read_line
      elseif (Reason > 0) then ! couldn't read the line
         write(*,'(a,i5,a)') 'Could not read line ', count_lines, ' in file input file after line: '//read_line
      else
         read(read_next_line,*, IOSTAT=Reason) numpar%Smear_DOS ! [eV] smearing function for DOS
         if (Reason /= 0) then
            write(*,'(a,i5,a)') 'Could not read SMEARING DOS parameter from line ', count_lines, ' in file input file after line: '//read_line
            write(*,'(a)') 'Using default values instead...'
            numpar%Smear_DOS = 0.05d0	! [eV]
         endif
      endif
   !---------------------------------------------------------------
   case ('PRINT_fe', 'Print_fe', 'print_fe', 'print_distribution')
      numpar%save_fe = .true.	! included printout distribution function
   !---------------------------------------------------------------
   case ('PRINT_PCF', 'Print_PCF', 'print_PCD', 'print_pair_correlation_function')
      numpar%save_PCF = .true.	! included printout pair correlation function
   !---------------------------------------------------------------
   case ('PRINT_XYZ', 'Print_XYZ', 'print_XYZ', 'print_xyz_format')
      numpar%save_XYZ = .true.	! included printout atomic coordinates in XYZ format
   case ('NO_XYZ', 'No_XYZ', 'no_XYZ', 'no_xyz_format')
      numpar%save_XYZ = .false.	! excluded printout atomic coordinates in XYZ format
   !---------------------------------------------------------------
   case ('PRINT_CIF', 'Print_CIF', 'print_CIF', 'print_cif')
      numpar%save_CIF = .true.	! included printout atomic coordinates in CIF format
   case ('NO_CIF', 'No_CIF', 'no_CIF', 'no_cif_format')
      numpar%save_CIF = .false.	! excluded printout atomic coordinates in CIF format
   !---------------------------------------------------------------
   case ('PRINT_RAW', 'Print_RAW', 'print_RAW', 'print_raw')
      numpar%save_raw = .true.	! included printout of raw data on atomic coordinates and velocities
   case ('NO_RAW', 'No_RAW', 'no_RAW', 'no_raw_data')
      numpar%save_raw = .false.	! excluded printout of raw data on atomic coordinates and velocities
   !---------------------------------------------------------------
   case ('OPTICAL_N_K', 'Optical_n_k', 'optical_n_k')
   read(FN,'(a)',IOSTAT=Reason) read_next_line
      count_lines = count_lines + 1   
      if (Reason < 0) then ! end of file
         write(*,'(a)') 'Clould not complete action: end of input file after line: '//read_line
      elseif (Reason > 0) then ! couldn't read the line
         write(*,'(a,i5,a)') 'Could not read line ', count_lines, ' in file input file after line: '//read_line
      else
         read(read_next_line,*, IOSTAT=Reason) Scell(1)%eps%n, Scell(1)%eps%k	! initial n and k coeffs
         if (Reason /= 0) then
            write(*,'(a,i5,a)') 'Could not read OPTICAL_N_K parameteres from line ', count_lines, ' in file input file after line: '//read_line
            write(*,'(a)') 'Using default values instead...'
            Scell(1)%eps%n = 1.0d0
            Scell(1)%eps%k = 0.0d0	! initial n and k coeffs
         endif
      endif
   !---------------------------------------------------------------
   case ('K_POINTS', 'K_points', 'k_points')
   read(FN,'(a)',IOSTAT=Reason) read_next_line
      count_lines = count_lines + 1   
      if (Reason < 0) then ! end of file
         write(*,'(a)') 'Clould not complete action: end of input file after line: '//read_line
      elseif (Reason > 0) then ! couldn't read the line
         write(*,'(a,i5,a)') 'Could not read line ', count_lines, ' in file input file after line: '//read_line
      else
         read(read_next_line,*, IOSTAT=Reason) numpar%ixm, numpar%iym, numpar%izm 
         if (Reason /= 0) then
            write(*,'(a,i5,a)') 'Could not read K_POINTS from line ', count_lines, ' in file input file after line: '//read_line
            write(*,'(a)') 'Using default values instead...'
            ! number of k-points in each direction (used only for Trani-k!):
            numpar%ixm = 1
            numpar%iym = 1
            numpar%izm = 1
         endif
      endif
   !---------------------------------------------------------------
   case ('EFFECTIVE_MASSES', 'Effective_masses', 'effective_masses', 'me_eff')
   read(FN,'(a)',IOSTAT=Reason) read_next_line
      count_lines = count_lines + 1   
      if (Reason < 0) then ! end of file
         write(*,'(a)') 'Clould not complete action: end of input file after line: '//read_line
      elseif (Reason > 0) then ! couldn't read the line
         write(*,'(a,i5,a)') 'Could not read line ', count_lines, ' in file input file after line: '//read_line
      else
         read(read_next_line,*, IOSTAT=Reason) Scell(1)%eps%me_eff, Scell(1)%eps%mh_eff
         if (Reason /= 0) then
            write(*,'(a,i5,a)') 'Could not read EFFECTIVE_MASSES from line ', count_lines, ' in file input file after line: '//read_line
            write(*,'(a)') 'Using default values instead...'
            ! [me] effective mass of CB electron and VB hole:
            Scell(1)%eps%me_eff = 1.0d0
            Scell(1)%eps%mh_eff = 1.0d0
         endif
         Scell(1)%eps%me_eff = Scell(1)%eps%me_eff*g_me	! [kg]
         Scell(1)%eps%mh_eff = Scell(1)%eps%mh_eff*g_me	! [kg]
      endif
   !---------------------------------------------------------------
   case ('SCATTERING_TIMES', 'Scattering_times', 'scattering_times', 'tau_eff')
   read(FN,'(a)',IOSTAT=Reason) read_next_line
      count_lines = count_lines + 1   
      if (Reason < 0) then ! end of file
         write(*,'(a)') 'Clould not complete action: end of input file after line: '//read_line
      elseif (Reason > 0) then ! couldn't read the line
         write(*,'(a,i5,a)') 'Could not read line ', count_lines, ' in file input file after line: '//read_line
      else
         read(read_next_line,*, IOSTAT=Reason) Scell(1)%eps%tau_e, Scell(1)%eps%tau_h
         if (Reason /= 0) then
            write(*,'(a,i5,a)') 'Could not read EFFECTIVE_MASSES from line ', count_lines, ' in file input file after line: '//read_line
            write(*,'(a)') 'Using default values instead...'
            ! [fs] mean scattering times of electrons and holes:
            Scell(1)%eps%tau_e = 1.0d0
            Scell(1)%eps%tau_h = 1.0d0
         endif
      endif
   !---------------------------------------------------------------
   case default ! just skip the line that is not interpretable
      select case (read_line(1:1))
      case ('!', 'c', 'C', '%', '#')
         ! this is a commentary line, just skip it
      case default
         print*, 'Could not interpret the line from input file: ', read_line
      endselect
   endselect
   !---------------------------------------------------------------
end subroutine interpret_input_line



end MODULE Read_input_data

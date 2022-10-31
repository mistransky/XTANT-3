! 000000000000000000000000000000000000000000000000000000000000
! This file is part of XTANT
!
! Copyright (C) 2016-2022 Nikita Medvedev
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
! This module contains subroutines to set initial conditions:

MODULE Initial_configuration
use Universal_constants
use Objects
!use Variables
use Algebra_tools
use Dealing_with_files
use Atomic_tools
use TB, only : get_DOS_masks, get_Hamilonian_and_E, get_glob_energy
use Dealing_with_BOP, only : m_repulsive, m_N_BOP_rep_grid
use ZBL_potential, only : ZBL_pot
use TB_xTB, only : identify_xTB_orbitals_per_atom
use Little_subroutines

implicit none

 contains




subroutine create_BOP_repulsive(Scell, matter, numpar, TB_Repuls, i, j, Folder_name, path_sep, Name1, Name2, bond_length_in, Elem1, Elem2, Err)
   type(Super_cell), dimension(:), intent(inout) :: Scell ! suoer-cell with all the atoms inside
   type(Solid), intent(inout) :: matter	! all material parameters
   type(Numerics_param), intent(inout) :: numpar 	! all numerical parameters
   type(TB_Rep_BOP), dimension(:,:), intent(inout) ::  TB_Repuls    ! parameters of the repulsive potential
   integer, intent(in) :: i, j  ! numbers of pair of elements for which we read the data
   character(*), intent(in) :: Folder_name    ! directory where to find BOP parameters
   character(1), intent(in) :: path_sep
   character(*), intent(in) :: Name1, Name2 ! element names
   real(8), intent(in) :: bond_length_in   ! [A] bond length for dimer
   real(8), intent(in) :: Elem1, Elem2  ! atomic numbers of the two elements we need the parameters for
   type(Error_handling), intent(inout) :: Err	! error save
   !-------------------
   character(300) :: File_name, Error_descript
   integer :: FN_BL, k, NSC, n1, icur
   real(8) :: r_start, r_stop, dr, supcesize, Pot_shift, d_bond, ZBL_length, TB_d, ZBL_d, bond_length
   real(8), dimension(m_N_BOP_rep_grid) :: Ref_Pot, V_rep

   ! Region around the bond length where we smoothen the potentials:
   d_bond = 0.3d0   ! [A]
   ! Shifted bond length for fitting:
   bond_length = bond_length_in + d_bond    ! [A]

   ! Create repulsive potential:
   if (.not.allocated(TB_Repuls(i,j)%R)) then
      allocate(TB_Repuls(i,j)%R(m_N_BOP_rep_grid))
      ! Create grid:
      r_start = max(0.25d0, min(bond_length-0.5d0, 1.0d0) ) ! start of the grid [A]
      r_stop = bond_length + d_bond ! end of the grid [A]
      dr = (r_stop - r_start)/dble(m_N_BOP_rep_grid-1)   ! step set to have fixed number of points equal to m_N_BOP_rep_grid
      ! Save the grid:
      TB_Repuls(i,j)%R(1) = r_start ! [A]
      do k = 2, m_N_BOP_rep_grid
         TB_Repuls(i,j)%R(k) = TB_Repuls(i,j)%R(k-1) + dr   ! [A]
      enddo
   endif
   if (.not.allocated(TB_Repuls(i,j)%V_rep)) allocate(TB_Repuls(i,j)%V_rep(m_N_BOP_rep_grid))

   ! Get the reference potential (ZBL):
   do k = 1, m_N_BOP_rep_grid
      Ref_Pot(k) =  ZBL_pot(Elem1, Elem2, TB_Repuls(i,j)%R(k))  ! module "ZBL_potential"
!       print*, k, TB_Repuls(i,j)%R(k), Ref_Pot(k)
   enddo

   ! Set the equilibrium distance between the dimer atoms to get the correct bond length:
   supcesize = 10.0d0 * TB_Repuls(i,j)%R(m_N_BOP_rep_grid)  ! large supercell size to exclude periodicity
   Scell(1)%supce = RESHAPE( (/ supcesize, 0.0d0, 0.0d0,  &
                                0.0d0, supcesize, 0.0d0,  &
                                0.0d0, 0.0d0, supcesize /), (/3,3/) )
   Scell(1)%supce0 = Scell(1)%supce

   ! Place dimer along X axis at the distance of bond length:
   allocate(Scell(1)%MDatoms(2))    ! dimer
   Scell(1)%Na = 2
   Scell(1)%Ne = SUM(matter%Atoms(:)%NVB*matter%Atoms(:)%percentage)/SUM(matter%Atoms(:)%percentage)*Scell(1)%Na
   Scell(1)%Ne_low = Scell(1)%Ne ! at the start, all electrons are low-energy
   Scell(1)%Ne_high = 0.0d0 ! no high-energy electrons at the start
   Scell(1)%Ne_emit = 0.0d0 ! no emitted electrons at the start
   ! Allocate arrays for calculation of hamiltonian and related stuff:
   allocate(Scell(1)%Near_neighbor_list(Scell(1)%Na,Scell(1)%Na))  ! nearest neighbors
   allocate(Scell(1)%Near_neighbor_dist(Scell(1)%Na,Scell(1)%Na,4))  ! [A] distances
   allocate(Scell(1)%Near_neighbor_dist_s(Scell(1)%Na,Scell(1)%Na,3)) ! relative dist.
   allocate(Scell(1)%Near_neighbor_size(Scell(1)%Na)) ! how many nearest neighbours
   allocate(Scell(1)%Near_neighbors_user(Scell(1)%Na))
   ASSOCIATE (ARRAY => Scell(i)%TB_Hamil(:,:))
   select type(ARRAY)
   type is (TB_H_BOP)   ! it can be various basis sets:
     select case (numpar%N_basis_size)    ! find which one is used now:
     case (0)    ! s
        n1 = 1.0d0*Scell(i)%Na ! number of energy levels is defined by the number of TB parameters included
     case (1)    ! sp3
        n1 = 4.0d0*Scell(i)%Na ! number of energy levels is defined by the number of TB parameters included
     case default    ! sp3d5
        n1 = 9.0d0*Scell(i)%Na ! number of energy levels is defined by the number of TB parameters included
     endselect
   endselect
   END ASSOCIATE
   allocate(Scell(1)%Ha(n1,n1))   ! hamiltonian size
   allocate(Scell(1)%Ha0(n1,n1)) ! hamiltonian0 size
   allocate(Scell(1)%H_non(n1,n1))	! nondiagonalized Hamiltonian
   allocate(Scell(1)%H_non0(n1,n1))	! nondiagonalized Hamiltonian
   allocate(Scell(1)%Ei(n1))  ! energy levels, eigenvalues of the hamiltonian matrix
   allocate(Scell(1)%Ei0(n1))  ! energy levels0, eigenvalues of the hamiltonian matrix
   allocate(Scell(1)%Aij(n1,n1))	! coefficients used for forces in TB
   allocate(Scell(1)%fe(size(Scell(1)%Ei))) ! electron distribution function (Fermi-function)
   if (numpar%do_kappa) then
      allocate(Scell(1)%I_ij(size(Scell(1)%Ei))) ! electron-ion collision integral
      allocate(Scell(1)%Ce_i(size(Scell(1)%Ei))) ! electron-energy resolved heat capacity
   endif
   Scell(1)%MDatoms(1)%KOA = i
   Scell(1)%MDatoms(2)%KOA = j
   Scell(1)%MDatoms(1)%S(:) = 0.1d0
   !Scell(1)%MDatoms(2)%S(1) = 0.2d0
   !Scell(1)%MDatoms(2)%S(1) = Scell(1)%MDatoms(1)%S(1) + TB_Repuls(i,j)%R(m_N_BOP_rep_grid) / supcesize
   Scell(1)%MDatoms(2)%S(1) = Scell(1)%MDatoms(1)%S(1) + bond_length / supcesize
   Scell(1)%MDatoms(2)%S(2:3) = 0.1d0
   call Det_3x3(Scell(1)%supce, Scell(1)%V)
   call Coordinates_rel_to_abs(Scell, 1, if_old=.true.)    ! from the module "Atomic_tools"
   call get_DOS_masks(Scell, matter, numpar)  ! module "TB"

   ! Get the energy shift:
   ! Contruct TB Hamiltonian, diagonalize to get energy levels, get forces for atoms and supercell:
   call get_Hamilonian_and_E(Scell, numpar, matter, 1, Err, 0.0d0) ! module "TB"
   ! Get global energy of the system at the beginning:
   call get_glob_energy(Scell, matter) ! module "Electron_tools"

   ! Energy shift:
   !Pot_shift = -Ref_Pot(m_N_BOP_rep_grid) + Scell(1)%nrg%El_low   ! [eV]
   Pot_shift = -ZBL_pot(Elem1, Elem2, bond_length) + Scell(1)%nrg%El_low   ! [eV]
   ! Shift potential accordingly, to produce correct minimum at bond length:
   Ref_Pot = Ref_Pot + Pot_shift

   ! Also define TB potential at the point of bond length + d:
   Scell(1)%MDatoms(2)%S(1) = Scell(1)%MDatoms(1)%S(1) + (bond_length+d_bond) / supcesize
   call Det_3x3(Scell(1)%supce, Scell(1)%V)
   call Coordinates_rel_to_abs(Scell, 1, if_old=.true.)    ! from the module "Atomic_tools"
   call get_DOS_masks(Scell, matter, numpar)  ! module "TB"
   call get_Hamilonian_and_E(Scell, numpar, matter, 1, Err, 0.0d0) ! module "TB"
   call get_glob_energy(Scell, matter) ! module "Electron_tools"
   TB_d = Scell(1)%nrg%El_low   ! [eV]

   ! Also define ZBL potential at the point of bond length - d:
   call Find_in_array_monoton(abs(Ref_Pot), abs(TB_d), icur) ! module "Little_subroutines"
   call linear_interpolation(Ref_Pot, TB_Repuls(i,j)%R, TB_d, ZBL_length, icur) ! module "Algebra_tools"

!    do k = 1, m_N_BOP_rep_grid
!       print*, k, TB_Repuls(i,j)%R(k), Ref_Pot(k)
!    enddo
!     print*, 'ZBL_length', ZBL_length, TB_d, icur, Ref_Pot(icur), TB_Repuls(i,j)%R(icur)


   ! Calculate the repulsive term, such that total potential equals the referenced one:
   do k = 1, m_N_BOP_rep_grid
      ! Set the distance according to grid point for repulsive potential:
      Scell(1)%MDatoms(2)%S(1) = Scell(1)%MDatoms(1)%S(1) + TB_Repuls(i,j)%R(k) / supcesize
      call Coordinates_rel_to_abs(Scell, 1, if_old=.true.)    ! from the module "Atomic_tools"
      call get_Hamilonian_and_E(Scell, numpar, matter, 1, Err, 0.0d0) ! module "TB"
      ! Get global energy of the system at the beginning:
      call get_glob_energy(Scell, matter) ! module "Electron_tools"
      ! Set the repulsive potential:
      if ( TB_Repuls(i,j)%R(k) <= ZBL_length ) then
         V_rep(k) = Ref_Pot(k) - Scell(1)%nrg%El_low    ! [eV]
         ZBL_d = V_rep(k)
      else
         ZBL_d = 1.0d0 / (1.0d0/(Ref_Pot(k)-TB_d) + 1.0d0/(Scell(1)%nrg%El_low-TB_d))
         V_rep(k) = (TB_d + ZBL_d) - Scell(1)%nrg%El_low   ! [eV]
      endif
!       write(*,'(i3,f,f,es,es,es,f,f)') k, TB_Repuls(i,j)%R(k), V_rep(k),  (1.0d0/(Ref_Pot(k)-TB_d) + 1.0d0/(Scell(1)%nrg%El_low-TB_d)), ZBL_d, TB_d - Scell(1)%nrg%El_low, TB_Repuls(i,j)%R(k), ZBL_length
   enddo
   TB_Repuls(i,j)%V_rep = V_rep ! save it
!    print*, 'Pot_shift', Pot_shift, supcesize, sqrt(SUM((Scell(1)%MDatoms(1)%R(:)-Scell(1)%MDatoms(2)%R(:))**2))

   ! Restore the parameters:
   deallocate(Scell(1)%MDatoms)
   deallocate(Scell(1)%Near_neighbor_list)  ! nearest neighbors
   deallocate(Scell(1)%Near_neighbor_dist)  ! [A] distances
   deallocate(Scell(1)%Near_neighbor_dist_s) ! relative dist.
   deallocate(Scell(1)%Near_neighbor_size) ! how many nearest neighbours
   deallocate(Scell(1)%Near_neighbors_user)
   deallocate(Scell(1)%Ha)
   deallocate(Scell(1)%Ha0)
   deallocate(Scell(1)%H_non)
   deallocate(Scell(1)%H_non0)
   deallocate(Scell(1)%Ei)
   deallocate(Scell(1)%Ei0)
   deallocate(Scell(1)%Aij)
   deallocate(Scell(1)%fe)
   deallocate(Scell(1)%G_ei_partial)
   deallocate(Scell(1)%Ce_part)
   call deallocate_array(Scell(1)%I_ij)      ! module "Little_subroutines"
   call deallocate_array(Scell(1)%Norm_WF)   ! module "Little_subroutines"
   call deallocate_array(Scell(1)%Ce_i)      ! module "Little_subroutines"
   call deallocate_array(Scell(1)%kappa_e_part)   ! module "Little_subroutines"
   deallocate(numpar%mask_DOS)

!    pause 'create_BOP_repulsive'

   if (j /= i) then ! and the lower triangle
      if (.not.allocated( TB_Repuls(j,i)%R)) allocate(TB_Repuls(j,i)%R(m_N_BOP_rep_grid))
      if (.not.allocated( TB_Repuls(j,i)%V_rep)) allocate(TB_Repuls(j,i)%V_rep(m_N_BOP_rep_grid))
      TB_Repuls(j,i)%R(:) = TB_Repuls(i,j)%R(:)
      TB_Repuls(j,i)%V_rep(:) = TB_Repuls(i,j)%V_rep(:)
   endif

   ! File with repulsive BOP potential to be created:
   File_name = trim(adjustl(Folder_name))//path_sep// &
      trim(adjustl(Name1))//'_'//trim(adjustl(Name2))//trim(adjustl(m_repulsive))   ! file with repulsive BOP parameters
   FN_BL = 113
   open(UNIT=FN_BL, FILE = trim(adjustl(File_name)))
   ! Write into the file:
   do k = 1, m_N_BOP_rep_grid    ! for all grid points
      write(FN_BL,'(f24.16, es24.16)') TB_Repuls(i,j)%R(k), TB_Repuls(i,j)%V_rep(k)
   enddo
   call close_file('close', FN=FN_BL) ! module "Dealing_with_files"

3415 continue
end subroutine create_BOP_repulsive




subroutine set_initial_configuration(Scell, matter, numpar, laser, MC, Err)
   type(Super_cell), dimension(:), allocatable, intent(inout) :: Scell ! suoer-cell with all the atoms inside
   type(Solid), intent(inout) :: matter	! all material parameters
   type(Numerics_param), intent(inout) :: numpar 	! all numerical parameters
   type(Pulse), dimension(:), allocatable, intent(inout) :: laser	! Laser pulse parameters
   type(MC_data), dimension(:), allocatable, intent(inout) :: MC ! all MC parameters
   type(Error_handling), intent(inout) :: Err	! error save
   !========================================================
   integer i, Nsc, Natoms, FN, FN2, Reason, count_lines, N, j, k, n1, FN3, FN4
   character(200) :: File_name, File_name2, Error_descript, File_name_S1, File_name_S2
   logical :: file_exist, file_opened, read_well, file_exist_1, file_exist_2
   real(8) RN, temp, Mass, V2, Ta

   Nsc = 1 !in the present version of the code, there is always only one super-cell

   ! If file with BOP repulsive potential does not exist, crete it:
   if (numpar%create_BOP_repulse) then
      do i = 1, size(Scell(NSC)%TB_Repuls,1)
         do j = 1, size(Scell(NSC)%TB_Repuls,2)
            ASSOCIATE (TB_Repuls => Scell(NSC)%TB_Repuls)
               select type(TB_Repuls)
               type is (TB_Rep_BOP)
                  call create_BOP_repulsive(Scell, matter, numpar, TB_Repuls, i, j, numpar%BOP_Folder_name, numpar%path_sep, &
                     trim(adjustl(matter%Atoms(i)%Name)), trim(adjustl(matter%Atoms(j)%Name)), &
                     numpar%BOP_bond_length, matter%Atoms(i)%Z, matter%Atoms(j)%Z, Err) ! above
               endselect
            END ASSOCIATE
         enddo ! j
      enddo ! i
   endif

   MD:if (matter%cell_x*matter%cell_y*matter%cell_z .GT. 0) then  ! only then there is something to do with atoms:
      if (.not.allocated(Scell)) allocate(Scell(Nsc))
      ALL_SC: do i = 1, Nsc
         
         numpar%do_path_coordinate = .false. ! to check files with phase 1 and 2
         
         ! Supercell vectors:
         FN3 = 9002
         FN4 = 9003
         write(File_name_S1, '(a,a,a)') trim(adjustl(numpar%input_path)), trim(adjustl(matter%Name))//numpar%path_sep, 'PHASE_1_supercell.dat'
         inquire(file=trim(adjustl(File_name_S1)),exist=file_exist_1)
         write(File_name_S2, '(a,a,a)') trim(adjustl(numpar%input_path)), trim(adjustl(matter%Name))//numpar%path_sep, 'PHASE_2_supercell.dat'
         inquire(file=trim(adjustl(File_name_S2)),exist=file_exist_2)
         ! Check if user set to calculate along path coordinate:
         numpar%do_path_coordinate = (file_exist_1 .and. file_exist_2)
         
         FN = 9000
         write(File_name, '(a,a,a)') trim(adjustl(numpar%input_path)), trim(adjustl(matter%Name))//numpar%path_sep, 'SAVE_supercell.dat'
         inquire(file=trim(adjustl(File_name)),exist=file_exist)
         
         SAVED_SUPCELL:if (numpar%do_path_coordinate) then ! read phase 1 and 2 supercells:
            
            ! Read phase 1 parameters:
            inquire(file=trim(adjustl(File_name_S1)),exist=file_exist)
            INPUT_PHASE_1:if (file_exist) then
               open(UNIT=FN3, FILE = trim(adjustl(File_name_S1)), status = 'old', action='read')
               inquire(file=trim(adjustl(File_name_S1)),opened=file_opened)
               if (.not.file_opened) then
                  Error_descript = 'File '//trim(adjustl(File_name_S1))//' could not be opened, the program terminates'
                  call Save_error_details(Err, 2, Error_descript)
                  print*, trim(adjustl(Error_descript))
                  goto 3416
               endif

               ! Read the supercell parameters of the initial phase:
               call get_supercell_vectors(FN3, File_name_S1, Scell, i, 1, matter, Err, ind=0) ! see below

            else INPUT_PHASE_1
               write(Error_descript,'(a,$)') 'File '//trim(adjustl(File_name_S1))//' could not be found, the program terminates'
               call Save_error_details(Err, 1, Error_descript)
               print*, trim(adjustl(Error_descript))
               goto 3416
            endif INPUT_PHASE_1
            
            ! Read phase 2 parameters:
            inquire(file=trim(adjustl(File_name_S2)),exist=file_exist)
            INPUT_PHASE_2:if (file_exist) then
               open(UNIT=FN4, FILE = trim(adjustl(File_name_S2)), status = 'old', action='read')
               inquire(file=trim(adjustl(File_name_S2)),opened=file_opened)
               if (.not.file_opened) then
                  Error_descript = 'File '//trim(adjustl(File_name_S2))//' could not be opened, the program terminates'
                  call Save_error_details(Err, 2, Error_descript)
                  print*, trim(adjustl(Error_descript))
                  goto 3416
               endif
               
               ! Read the supercell parameters of the final phase:
               call get_supercell_vectors(FN4, File_name_S2, Scell, i, 1, matter, Err, ind=1) ! see below
               
            else INPUT_PHASE_2
               write(Error_descript,'(a,$)') 'File '//trim(adjustl(File_name_S2))//' could not be found, the program terminates'
               call Save_error_details(Err, 1, Error_descript)
               print*, trim(adjustl(Error_descript))
               goto 3416
            endif INPUT_PHASE_2
            
            numpar%do_path_coordinate = .false. ! to check again files with atomic coordinates below
            inquire(file=trim(adjustl(File_name_S1)),opened=file_opened)
            if (file_opened) close (FN3)
            inquire(file=trim(adjustl(File_name_S2)),opened=file_opened)
            if (file_opened) close (FN4)
         
         elseif (file_exist) then SAVED_SUPCELL  ! read from this file with transient Super cell:
            inquire(file=trim(adjustl(File_name)),exist=file_exist)
            INPUT_SUPCELL:if (file_exist) then
               open(UNIT=FN, FILE = trim(adjustl(File_name)), status = 'old', action='read')
               inquire(file=trim(adjustl(File_name)),opened=file_opened)
               if (.not.file_opened) then
                  Error_descript = 'File '//trim(adjustl(File_name))//' could not be opened, the program terminates'
                  call Save_error_details(Err, 2, Error_descript)
                  print*, trim(adjustl(Error_descript))
                  goto 3416
               endif

               call get_supercell_vectors(FN, File_name, Scell, i, 1, matter, Err) ! see below

            else INPUT_SUPCELL
               write(Error_descript,'(a,$)') 'File '//trim(adjustl(File_name))//' could not be found, the program terminates'
               call Save_error_details(Err, 1, Error_descript)
               print*, trim(adjustl(Error_descript))
               goto 3416
            endif INPUT_SUPCELL
         else SAVED_SUPCELL
            write(File_name,'(a,a,a)') trim(adjustl(numpar%input_path)), &
                                trim(adjustl(matter%Name))//trim(adjustl(numpar%path_sep)), 'Unit_cell_equilibrium.txt'
            inquire(file=trim(adjustl(File_name)),exist=file_exist)
            INPUT_SUPCELL2:if (file_exist) then
               open(UNIT=FN, FILE = trim(adjustl(File_name)), status = 'old', action='read')
               inquire(file=trim(adjustl(File_name)),opened=file_opened)
               if (.not.file_opened) then
                  Error_descript = 'File '//trim(adjustl(File_name))//' could not be opened, the program terminates'
                  call Save_error_details(Err, 2, Error_descript)
                  print*, trim(adjustl(Error_descript))
                  goto 3416
               endif

               call get_supercell_vectors(FN, File_name, Scell, i, 2, matter, Err) ! see below

            else INPUT_SUPCELL2
               write(Error_descript,'(a,$)') 'File '//trim(adjustl(File_name))//' could not be found, the program terminates'
               call Save_error_details(Err, 1, Error_descript)
               print*, trim(adjustl(Error_descript))
               goto 3416
            endif INPUT_SUPCELL2
         endif SAVED_SUPCELL
         inquire(file=trim(adjustl(File_name)),opened=file_opened)
         if (file_opened) close (FN)
        
         
         ! Check how to set the atomic coordinates:
         ! a) If user wants path coordinates:
         write(File_name_S1, '(a,a,a)') trim(adjustl(numpar%input_path)), trim(adjustl(matter%Name))//numpar%path_sep, 'PHASE_1_atoms.dat'
         inquire(file=trim(adjustl(File_name_S1)),exist=file_exist_1)
         write(File_name_S2, '(a,a,a)') trim(adjustl(numpar%input_path)), trim(adjustl(matter%Name))//numpar%path_sep, 'PHASE_2_atoms.dat'
         inquire(file=trim(adjustl(File_name_S2)),exist=file_exist_2)
         ! Check if user set to calculate along path coordinate:
         numpar%do_path_coordinate = (file_exist_1 .and. file_exist_2)

         ! b) if user set atomic positions in relative units within the supercell:
         FN2 = 9001
         write(File_name2, '(a,a,a)') trim(adjustl(numpar%input_path)), trim(adjustl(matter%Name))//numpar%path_sep, 'SAVE_atoms.dat'
         inquire(file=trim(adjustl(File_name2)),exist=file_exist)
            
         ! Select among different possibilities to set the atomic cell:
         SAVED_ATOMS:if (numpar%do_path_coordinate) then ! read from the files with initial and final configurations to do the path coordinate plots

            inquire(file=trim(adjustl(File_name_S1)),opened=file_opened)
            if (file_opened) close (FN3)
            inquire(file=trim(adjustl(File_name_S2)),opened=file_opened)
            if (file_opened) close (FN4)
            
            ! Get the phase 1 coordinates:
            open(UNIT=FN3, FILE = trim(adjustl(File_name_S1)), status = 'old', action='read')
            call get_initial_atomic_coord(FN3, File_name_S1, Scell, i, 1, matter, Err, ind = 0) ! below
            ! Get the phase 2 coordinates:
            open(UNIT=FN4, FILE = trim(adjustl(File_name_S2)), status = 'old', action='read')
            call get_initial_atomic_coord(FN4, File_name_S2, Scell, i, 1, matter, Err, ind = 1) ! below
            
            ! Get atomic temperature set by the velocities given in the SAVE file:
            Natoms = size(Scell(i)%MDatoms)	! number of atoms
            Ta = 0.0d0 ! atomic temperature
            do j = 1,Natoms	! all atoms:
               V2 = SUM(Scell(i)%MDatoms(j)%V(:)*Scell(i)%MDatoms(j)%V(:))*1d10 ! abs value of velocity [A/fs]^2 -> [m/s]^2
               Mass = matter%Atoms(Scell(i)%MDatoms(j)%KOA)%Ma ! atomic mass
               Ta = Ta + Mass*V2/2.0d0/g_e ! Temperature [eV], Eq.(2.62) from H.Jeschke PhD thesis, p.49
            enddo
            Ta = Ta*2.0d0/(3.0d0*real(Natoms) - 6.0d0) ! [eV] proper normalization
            Ta = Ta*g_kb	! [eV] -> [K]

            if (max(Ta,Scell(i)%Ta)/min(Ta+1d-6,Scell(i)%Ta+1d-6) > 1.5d0) then ! if given temperature is too different from the initial one
               ! Set initial velocities according to the given input temperature:
               call set_initial_velocities(matter,Scell,i,Scell(i)%MDatoms,numpar,numpar%allow_rotate) ! module "Atomic_tools"
            endif
         
         elseif (file_exist) then SAVED_ATOMS    ! read from this file with transient Super cell:
            open(UNIT=FN2, FILE = trim(adjustl(File_name2)), status = 'old', action='read')
            call get_initial_atomic_coord(FN2, File_name2, Scell, i, 1, matter, Err) ! below
            
            ! Get atomic temperature set by the velocities given in the SAVE file:
            Natoms = size(Scell(i)%MDatoms)	! number of atoms
            Ta = 0.0d0 ! atomic temperature
            do j = 1,Natoms	! all atoms:
               V2 = SUM(Scell(i)%MDatoms(j)%V(:)*Scell(i)%MDatoms(j)%V(:))*1d10 ! abs value of velocity [A/fs]^2 -> [m/s]^2
               Mass = matter%Atoms(Scell(i)%MDatoms(j)%KOA)%Ma ! atomic mass
               Ta = Ta + Mass*V2/2.0d0/g_e ! Temperature [eV], Eq.(2.62) from H.Jeschke PhD thesis, p.49
            enddo
            Ta = Ta*2.0d0/(3.0d0*real(Natoms) - 6.0d0) ! [eV] proper normalization
            Ta = Ta*g_kb	! [eV] -> [K]

            if (max(Ta,Scell(i)%Ta)/min(Ta+1d-6,Scell(i)%Ta+1d-6) > 1.5d0) then ! if given temperature is too different from the initial one
               ! Set initial velocities according to the given input temperature:
               call set_initial_velocities(matter,Scell,i,Scell(i)%MDatoms,numpar,numpar%allow_rotate)  ! below
            endif
         else SAVED_ATOMS
            ! c) if user set to construct supercell from unit cells:
            write(File_name2,'(a,a,a)') trim(adjustl(numpar%input_path)), trim(adjustl(matter%Name))//numpar%path_sep, 'Unit_cell_atom_relative_coordinates.txt'
            inquire(file=trim(adjustl(File_name)),exist=file_exist)
            INPUT_ATOMS:if (file_exist) then
               open(UNIT=FN2, FILE = trim(adjustl(File_name2)), status = 'old', action='read')
               inquire(file=trim(adjustl(File_name2)),opened=file_opened)
               if (.not.file_opened) then
                  Error_descript = 'File '//trim(adjustl(File_name2))//' could not be opened, the program terminates'
                  call Save_error_details(Err, 2, Error_descript)
                  print*, trim(adjustl(Error_descript))
                  goto 3416
               endif

               call get_initial_atomic_coord(FN2, File_name2, Scell, i, 2, matter, Err) ! below
               ! Set initial velocities:
               call set_initial_velocities(matter,Scell,i,Scell(i)%MDatoms,numpar,numpar%allow_rotate) ! below

            else INPUT_ATOMS
               write(Error_descript,'(a,$)') 'File '//trim(adjustl(File_name2))//' could not be found, the program terminates'
               call Save_error_details(Err, 1, Error_descript)
               print*, trim(adjustl(Error_descript))
               goto 3416
            endif INPUT_ATOMS
         endif SAVED_ATOMS
         inquire(file=trim(adjustl(File_name2)),opened=file_opened)
         if (file_opened) close (FN2)
         
         !---------------------------
         ! Check periodicity:
         call Make_free_surfaces(Scell, numpar, matter)	! module "Atomic_tools"
         !call Coordinates_rel_to_abs(Scell, i, if_old=.true.)	! from the module "Atomic_tools"
         ! Save atomic coordinates at their equilibrium positions:
         do j = 1, Scell(i)%Na
            Scell(i)%MDatoms(j)%R_eq(:) = Scell(i)%MDatoms(j)%R(:)	! save coords at equilibrium positions to ger mean square displacements later
            Scell(i)%MDatoms(j)%S_eq(:) = Scell(i)%MDatoms(j)%S(:)	! save coords at equilibrium positions to ger mean square displacements later
         enddo ! j
         !---------------------------
         

         ! Allocate nearest neighbor lists:
         if (.not.allocated(Scell(i)%Near_neighbor_list)) allocate(Scell(i)%Near_neighbor_list(Scell(i)%Na,Scell(i)%Na))  ! nearest neighbors
         if (.not.allocated(Scell(i)%Near_neighbor_dist)) allocate(Scell(i)%Near_neighbor_dist(Scell(i)%Na,Scell(i)%Na,4))  ! [A] distances
         if (.not.allocated(Scell(i)%Near_neighbor_dist_s)) allocate(Scell(i)%Near_neighbor_dist_s(Scell(i)%Na,Scell(i)%Na,3)) ! relative dist.
         if (.not.allocated(Scell(i)%Near_neighbor_size)) allocate(Scell(i)%Near_neighbor_size(Scell(i)%Na)) ! how many nearest neighbours
         if (numpar%save_NN) then   ! if user wants to study number of nearest neighbors within defined radius
            if (.not.allocated(Scell(i)%Near_neighbors_user)) allocate(Scell(i)%Near_neighbors_user(Scell(i)%Na)) ! user-defined nearest neighbours
         endif

         ! Allocate Hamiltonan matrices:
         !if (.not.allocated(Scell(i)%Ha)) allocate(Scell(i)%Ha(Scell(i)%Ne,Scell(i)%Ne))   ! hamiltonian size
         ASSOCIATE (ARRAY => Scell(i)%TB_Hamil(:,:))
            select type(ARRAY)
            type is (TB_H_Pettifor)
               n1 = size(ARRAY(i,i)%V0)*Scell(i)%Na ! number of energy levels is defined by the number of TB parameters included
            type is (TB_H_Molteni)
               n1 = size(ARRAY(i,i)%V0)*Scell(i)%Na ! number of energy levels is defined by the number of TB parameters included
            type is (TB_H_Fu)
               n1 = size(ARRAY(i,i)%V0)*Scell(i)%Na ! number of energy levels is defined by the number of TB parameters included
            type is (TB_H_NRL)	! it is always sp3d5 basis set, so 9 orbitals per atom:
               n1 = 9.0d0*Scell(i)%Na ! number of energy levels is defined by the number of TB parameters included
!                if (.not.allocated(Scell(i)%Vij)) allocate(Scell(i)%Vij(n1,n1))	! radial part of hamiltonian size
               if (.not.allocated(Scell(i)%Sij)) allocate(Scell(i)%Sij(n1,n1))	! Overlap matrix for non-orthogonal TB
               if (.not.allocated(Scell(i)%Hij)) allocate(Scell(i)%Hij(n1,n1))	! Non-orthogonal TB Hamiltonian
               if (.not.allocated(Scell(i)%Hij_sol)) allocate(Scell(i)%Hij_sol(n1,n1))	! eigenvectors of nondiagonalized Hamiltonian
            type is (TB_H_DFTB)   ! it can be various basis sets:
               select case (numpar%N_basis_size)    ! find which one is used now:
               case (0)    ! s
                  n1 = 1.0d0*Scell(i)%Na ! number of energy levels is defined by the number of TB parameters included
               case (1)    ! sp3
                  n1 = 4.0d0*Scell(i)%Na ! number of energy levels is defined by the number of TB parameters included
               case default    ! sp3d5
                  n1 = 9.0d0*Scell(i)%Na ! number of energy levels is defined by the number of TB parameters included
               endselect
               if (.not.allocated(Scell(i)%Sij)) allocate(Scell(i)%Sij(n1,n1))	! Overlap matrix for non-orthogonal TB
               if (.not.allocated(Scell(i)%Hij)) allocate(Scell(i)%Hij(n1,n1))	! Non-orthogonal TB Hamiltonian
               if (.not.allocated(Scell(i)%Hij_sol)) allocate(Scell(i)%Hij_sol(n1,n1))	! eigenvectors of nondiagonalized Hamiltonian
            type is (TB_H_3TB)   ! it can be various basis sets:
               select case (numpar%N_basis_size)    ! find which one is used now:
               case (0)    ! s
                  n1 = 1.0d0*Scell(i)%Na ! number of energy levels is defined by the number of TB parameters included
               case (1)    ! sp3
                  n1 = 4.0d0*Scell(i)%Na ! number of energy levels is defined by the number of TB parameters included
               case default    ! sp3d5
                  n1 = 9.0d0*Scell(i)%Na ! number of energy levels is defined by the number of TB parameters included
               endselect
               if (.not.allocated(Scell(i)%Sij)) allocate(Scell(i)%Sij(n1,n1))	! Overlap matrix for non-orthogonal TB
               if (.not.allocated(Scell(i)%Hij)) allocate(Scell(i)%Hij(n1,n1))	! Non-orthogonal TB Hamiltonian
               if (.not.allocated(Scell(i)%Hij_sol)) allocate(Scell(i)%Hij_sol(n1,n1))	! eigenvectors of nondiagonalized Hamiltonian
            type is (TB_H_BOP)   ! it can be various basis sets:
               select case (numpar%N_basis_size)    ! find which one is used now:
               case (0)    ! s
                  n1 = 1.0d0*Scell(i)%Na ! number of energy levels is defined by the number of TB parameters included
               case (1)    ! sp3
                  n1 = 4.0d0*Scell(i)%Na ! number of energy levels is defined by the number of TB parameters included
               case default    ! sp3d5
                  n1 = 9.0d0*Scell(i)%Na ! number of energy levels is defined by the number of TB parameters included
               endselect
               if (.not.allocated(Scell(i)%Sij)) allocate(Scell(i)%Sij(n1,n1))	! Overlap matrix for non-orthogonal TB
               if (.not.allocated(Scell(i)%Hij)) allocate(Scell(i)%Hij(n1,n1))	! Non-orthogonal TB Hamiltonian
               if (.not.allocated(Scell(i)%Hij_sol)) allocate(Scell(i)%Hij_sol(n1,n1))	! eigenvectors of nondiagonalized Hamiltonian
            type is (TB_H_xTB)
               ! number of energy levels is defined by the number of TB parameters included:
               n1 = identify_xTB_orbitals_per_atom(numpar%N_basis_size) * Scell(i)%Na ! module "TB_xTB"
               if (.not.allocated(Scell(i)%Sij)) allocate(Scell(i)%Sij(n1,n1))	! Overlap matrix for non-orthogonal TB
               if (.not.allocated(Scell(i)%Hij)) allocate(Scell(i)%Hij(n1,n1))	! Non-orthogonal TB Hamiltonian
               if (.not.allocated(Scell(i)%Hij_sol)) allocate(Scell(i)%Hij_sol(n1,n1))	! eigenvectors of nondiagonalized Hamiltonian
            end select
         END ASSOCIATE

         if (.not.allocated(Scell(i)%Ha)) allocate(Scell(i)%Ha(n1,n1))   ! hamiltonian size
         if (.not.allocated(Scell(i)%Ha0)) allocate(Scell(i)%Ha0(n1,n1)) ! hamiltonian0 size
         if (.not.allocated(Scell(i)%H_non)) allocate(Scell(i)%H_non(n1,n1))	! nondiagonalized Hamiltonian
         if (.not.allocated(Scell(i)%H_non0)) allocate(Scell(i)%H_non0(n1,n1))	! nondiagonalized Hamiltonian
         if (.not.allocated(Scell(i)%Ei)) allocate(Scell(i)%Ei(n1))  ! energy levels, eigenvalues of the hamiltonian matrix
         if (.not.allocated(Scell(i)%Ei0)) allocate(Scell(i)%Ei0(n1))  ! energy levels0, eigenvalues of the hamiltonian matrix
         if (.not.allocated(Scell(i)%Aij)) allocate(Scell(i)%Aij(n1,n1))	! coefficients used for forces in TB
         if ((numpar%scc) .and. (.not.allocated(Scell(i)%Ei_scc_part)) ) then
            allocate(Scell(i)%Ei_scc_part(n1))  ! energy levels of non-SCC part of the hamiltonian
         endif
         if (allocated(Scell(i)%Sij) .and. .not.allocated(Scell(i)%eigen_S)) allocate(Scell(i)%eigen_S(n1)) ! eigenvalues of Sij
         
         if (.not. allocated(Scell(i)%fe)) allocate(Scell(i)%fe(size(Scell(i)%Ei))) ! electron distribution function (Fermi-function)
         if (numpar%do_kappa) then
            if (.not. allocated(Scell(i)%I_ij)) allocate(Scell(i)%I_ij(size(Scell(i)%Ei))) ! electron distribution function (Fermi-function)
            if (.not. allocated(Scell(i)%Ce_i)) allocate(Scell(i)%Ce_i(size(Scell(i)%Ei))) ! electron distribution function (Fermi-function)
         endif
!          if (.not. allocated(Scell(i)%Norm_WF)) allocate(Scell(i)%Norm_WF(size(Scell(i)%Ei))) ! normalization coefficient of the wave function

         ! DOS masks if needed:
!          select case (numpar%DOS_splitting)
!          case (1)
            call get_DOS_masks(Scell, matter, numpar)  ! module "TB"
!          case default ! No need to sort DOS per orbitals:
!             call get_DOS_masks(Scell, matter, numpar, only_coupling=.true.)  ! module "TB" 
!          endselect
         
         do j = 1,size(laser) ! for each pulse:
            laser(j)%Fabs = laser(j)%F*real(Scell(i)%Na) ! total absorbed energy by supercell [eV]
            laser(j)%Nph = laser(j)%Fabs/laser(i)%hw     ! number of photons absorbed in supercell
         enddo

         temp = 0.0d0
         do j = 1, Scell(i)%Na
            temp = temp + matter%Atoms(Scell(i)%MDatoms(j)%KOA)%Ma ! total mass of all atoms in supercell
         enddo
         matter%W_PR = temp/matter%W_PR ! Mass of unit cell in the Parrinello-Rahman method [kg]

      enddo ALL_SC
   endif MD
3416 continue

   ! Initialize MC data:
   do Nsc = 1, size(Scell)
      if (.not. allocated(MC)) then
         Scell(Nsc)%Nph = 0.0d0		! number of absorbed photons
         Scell(Nsc)%Ne_high = 0.0d0	! no electrons at the beginning
         Scell(Nsc)%Ne_emit = 0.0d0	! no emitted electrons at the beginning
         Scell(Nsc)%Nh = 0.0d0		! no holes at the beginning
         allocate(Scell(Nsc)%MChole(size(matter%Atoms)))
         do i = 1, size(matter%Atoms) ! for each kind of atoms:
            allocate(Scell(Nsc)%MChole(i)%Noh(matter%Atoms(i)%sh))
            Scell(Nsc)%MChole(i)%Noh(:) = 0.0d0 ! no holes in any shell
         enddo
         if (numpar%NMC > 0) then
            allocate(MC(numpar%NMC))	! all MC arrays for photons, electrons and holes
         !if (size(MC) > 0) then
            do i = 1, size(MC)
               MC(i)%noe = 0.0d0
               MC(i)%noe_emit = 0.0d0
               MC(i)%noh_tot = 0.0d0
               allocate(MC(i)%electrons(Scell(Nsc)%Ne))
               MC(i)%electrons(:)%E = 0.0d0
               MC(i)%electrons(:)%ti = 1d25
               MC(i)%electrons(:)%colls = 0
               allocate(MC(i)%holes(Scell(Nsc)%Ne))
               MC(i)%holes(:)%E = 0.0d0
               MC(i)%holes(:)%ti = 1d26
            enddo
         endif !(size(MC) > 0)
      endif
   enddo

   ! If we didn't set the density for MC, use it from the MD part:
   if (matter%dens <= 0.0d0) then
      matter%At_dens = dble(Scell(1)%Na)/(Scell(1)%V*1.0d-24)
      matter%dens = matter%At_dens*(SUM(matter%Atoms(:)%Ma*matter%Atoms(:)%percentage)/(SUM(matter%Atoms(:)%percentage))*1d3) ! just in case there was no better given density (no cdf file was used)
   else
      matter%At_dens = matter%dens/(SUM(matter%Atoms(:)%Ma*matter%Atoms(:)%percentage)/(SUM(matter%Atoms(:)%percentage))*1d3)   ! atomic density [1/cm^3]
   endif

   
!     do i = 1, Scell(1)%Na
!        write(6,'(i4,f,f,f,f,f,f)') i, Scell(1)%MDAtoms(i)%S0(:), Scell(1)%MDAtoms(i)%S(:)
!     enddo ! j
!    pause 'set_initial_configuration'
end subroutine set_initial_configuration


subroutine get_initial_atomic_coord(FN, File_name, Scell, SCN, which_one, matter, Err, ind)
   integer, intent(in) :: FN, which_one, SCN ! file number; type of file to read from (2=unit-cell, 1=super-cell); number of supercell
   character(*), intent(in) :: File_name ! file with the super-cell parameters
   type(Super_cell), dimension(:), intent(inout) :: Scell ! suoer-cell with all the atoms inside
   type(Solid), intent(inout) :: matter	! all material parameters
   type(Error_handling), intent(inout) :: Err	! error save
   integer, intent(in), optional :: ind ! read files for phase path tracing
   !=====================================
   integer :: INFO, Na, i, j
   integer Reason, count_lines
   character(200) Error_descript
   logical read_well
   type(Atom), dimension(:), allocatable :: MDAtoms ! if more then one supercell

   select case (which_one)
   case (1) ! saved all atomic coordinates
      count_lines = 0
      call Count_lines_in_file(FN, Na) ! that's how many atoms we have
      
      if (present(ind)) then    ! reading data for two phases for path coordinate tracing
         if (ind == 0) then ! define the parameters:
            Scell(SCN)%Na = Na ! Number of atoms is defined this way
            Scell(SCN)%Ne = SUM(matter%Atoms(:)%NVB*matter%Atoms(:)%percentage)/SUM(matter%Atoms(:)%percentage)*Scell(SCN)%Na
            Scell(SCN)%Ne_low = Scell(SCN)%Ne ! at the start, all electrons are low-energy
            Scell(SCN)%Ne_high = 0.0d0 ! no high-energy electrons at the start
            Scell(SCN)%Ne_emit = 0.0d0 ! no emitted electrons at the start
         else ! do not redefine the parameters, but check for consistency
            if (Na /= Scell(SCN)%Na) then
               write(Error_descript,'(a)') 'Inconsistent numbers of atoms in the files PHASE_1_atoms.dat and PHASE_2_atoms.dat, terminating XTANT'
               call Save_error_details(Err, 3, Error_descript)
               print*, trim(adjustl(Error_descript))
               goto 3417
            endif
         endif
      else
         Scell(SCN)%Na = Na ! Number of atoms is defined this way
         !Scell(SCN)%Ne = matter%Atoms(1)%Ne_shell(matter%Atoms(1)%sh)*Scell(SCN)%Na	! number of valence electrons
         Scell(SCN)%Ne = SUM(matter%Atoms(:)%NVB*matter%Atoms(:)%percentage)/SUM(matter%Atoms(:)%percentage)*Scell(SCN)%Na
         Scell(SCN)%Ne_low = Scell(SCN)%Ne ! at the start, all electrons are low-energy
         Scell(SCN)%Ne_high = 0.0d0 ! no high-energy electrons at the start
         Scell(SCN)%Ne_emit = 0.0d0 ! no emitted electrons at the start
      endif
      
      if (.not.allocated(MDAtoms)) allocate(MDAtoms(Scell(SCN)%Na))
      if (.not.allocated(Scell(SCN)%MDAtoms)) allocate(Scell(SCN)%MDAtoms(Scell(SCN)%Na))
      
      do i = 1, Na ! read atomic data:
         !read(FN,*,IOSTAT=Reason) Scell(SCN)%MDAtoms(i)%KOA, Scell(SCN)%MDAtoms(i)%S(:), Scell(SCN)%MDAtoms(i)%S0(:), Scell(SCN)%MDAtoms(i)%SV(:), Scell(SCN)%MDAtoms(i)%SV0(:)
         read(FN,*,IOSTAT=Reason) MDAtoms(i)%KOA, MDAtoms(i)%S(:), MDAtoms(i)%S0(:), MDAtoms(i)%SV(:), MDAtoms(i)%SV0(:)
         call read_file(Reason, count_lines, read_well)
!          print*, 'Read:', i, Scell(SCN)%MDAtoms(i)%S(:), Scell(SCN)%MDAtoms(i)%SV(:)
         if (.not. read_well) then
            write(Error_descript,'(a,i3,a,$)') 'Could not read line ', count_lines, ' in file '//trim(adjustl(File_name))
            call Save_error_details(Err, 3, Error_descript)
            print*, trim(adjustl(Error_descript)), Reason
            goto 3417
         endif
      enddo
      
      if (present(ind)) then
         if (ind == 0) then ! initial phase
            do i = 1, Na ! read atomic data:
               Scell(SCN)%MDAtoms(i)%KOA = MDAtoms(i)%KOA
               Scell(SCN)%MDAtoms(i)%S0(:) = MDAtoms(i)%S0(:)
               Scell(SCN)%MDAtoms(i)%SV0(:) = MDAtoms(i)%SV0(:)
            enddo
         else   ! final phase
            do i = 1, Na ! read atomic data:
               Scell(SCN)%MDAtoms(i)%S(:) = MDAtoms(i)%S(:)
               Scell(SCN)%MDAtoms(i)%SV(:) = MDAtoms(i)%SV(:)
            enddo
            call Coordinates_rel_to_abs(Scell, SCN, if_old=.true.)	! from the module "Atomic_tools"
            call velocities_abs_to_rel(Scell, SCN, if_old=.true.)	! from the module "Atomic_tools"
         endif
      else
         Scell(SCN)%MDAtoms = MDAtoms
         call Coordinates_rel_to_abs(Scell, SCN, if_old=.true.)	! from the module "Atomic_tools"
         !call velocities_abs_to_rel(Scell, SCN, if_old=.true.)	! from the module "Atomic_tools"
         call velocities_rel_to_abs(Scell, SCN) ! get absolute velocities, module "Atomic_tools"
      endif
      
      if (.not.allocated(MDAtoms)) deallocate(MDAtoms)
   case default ! coordinates in the unit cell

      call set_initial_coords(matter, Scell, SCN, FN, File_name, INFO=INFO,Error_descript=Error_descript)
      if (INFO .NE. 0) then
         call Save_error_details(Err, INFO, Error_descript)
         goto 3417
      endif
   end select
   
   ! Save atomic coordinates at their equilibrium positions:
   if (present(ind)) then
      if (ind == 0) then ! initial phase
          do j = 1, Scell(SCN)%Na
            Scell(SCN)%MDatoms(j)%R_eq(:) = Scell(SCN)%MDatoms(j)%R0(:)	! save coords at equilibrium positions to ger mean square displacements later
            Scell(SCN)%MDatoms(j)%S_eq(:) = Scell(SCN)%MDatoms(j)%S0(:)	! save coords at equilibrium positions to ger mean square displacements later
         enddo ! j
      else   ! final phase
            ! has nothing to do here
      endif
   else
      do j = 1, Scell(SCN)%Na
         Scell(SCN)%MDatoms(j)%R_eq(:) = Scell(SCN)%MDatoms(j)%R(:)	! save coords at equilibrium positions to ger mean square displacements later
         Scell(SCN)%MDatoms(j)%S_eq(:) = Scell(SCN)%MDatoms(j)%S(:)	! save coords at equilibrium positions to ger mean square displacements later
      enddo ! j
   endif
   
   ! For Martyna algorithm (only start from zeros for now...):
   do i = 1, Scell(SCN)%Na
      Scell(SCN)%MDAtoms(i)%A = 0.0d0
      Scell(SCN)%MDAtoms(i)%A_tild(:) = 0.0d0
      Scell(SCN)%MDAtoms(i)%v_F = 0.0d0
      Scell(SCN)%MDAtoms(i)%v_J = 0.0d0
      Scell(SCN)%MDAtoms(i)%A0 = 0.0d0
      Scell(SCN)%MDAtoms(i)%A_tild0 = 0.0d0
      Scell(SCN)%MDAtoms(i)%v_F0 = 0.0d0
      Scell(SCN)%MDAtoms(i)%v_J0 = 0.0d0
   enddo
   
   
3417 continue

!    do i = 1, Scell(SCN)%Na
!       if (present(ind)) then
!          write(6,'(i4,f,f,f,f,f,f)') ind, Scell(SCN)%MDAtoms(i)%S0(:), Scell(SCN)%MDAtoms(i)%S(:)
!       else
!          write(6,'(a)') 'Subroutine get_initial_atomic_coord is called without ind'
!       endif
!    enddo ! j

end subroutine get_initial_atomic_coord



subroutine set_initial_coords(matter,Scell,SCN,FN,File_name,Nat,INFO,Error_descript)
   type(solid), intent(inout) :: matter	! materil parameters
   type(Super_cell), dimension(:), intent(inout) :: Scell ! suoer-cell with all the atoms inside
   integer, intent(in) :: SCN ! number of supercell
   integer, intent(in) :: FN	! file number for reading initial coordinates inside the unit-cell
   character(*), intent(in) :: File_name ! file name where to read from
   integer, optional :: Nat ! number of atoms in the unit cell
   integer, intent(out) :: INFO ! did we read well from the file
   real(8) a, b, l2, x, y, z, RN, epsylon, coord_shift
   integer i, j, k, ik, nx, ny, nz, ncellx, ncelly, ncellz, Na
   !real(8), dimension(3,8) :: Relcoat
   real(8), dimension(:,:), allocatable :: Relcoat
   integer Reason, count_lines
   character(200) Error_descript
   logical read_well

   epsylon = 1.0d-10    ! for tiny shift of coords
   
   INFO = 0 ! at the start there is no errors
   call Count_lines_in_file(FN, Na) ! that's how many atoms we have
   allocate(Relcoat(3,Na))

   Scell(SCN)%Na = Na*matter%cell_x*matter%cell_y*matter%cell_z ! Number of atoms is defined this way
   !Scell(SCN)%Ne = matter%Atoms(1)%Ne_shell(matter%Atoms(1)%sh)*Scell(SCN)%Na	! number of valence electrons
   Scell(SCN)%Ne = SUM(matter%Atoms(:)%NVB*matter%Atoms(:)%percentage)/SUM(matter%Atoms(:)%percentage)*Scell(SCN)%Na
   Scell(SCN)%Ne_low = Scell(SCN)%Ne ! at the start, all electrons are low-energy
   
   if (.not.allocated(Scell(SCN)%MDatoms)) allocate(Scell(SCN)%MDatoms(Scell(SCN)%Na))

   count_lines = 0
   do i = 1,Na
      read(FN,*,IOSTAT=Reason) Scell(SCN)%MDatoms(i)%KOA, Relcoat(:,i)	! relative coordinates of atoms in the unit-cell
      call read_file(Reason, count_lines, read_well)
      if (.not. read_well) then
         INFO = 3
         write(Error_descript,'(a,i3,a,$)') 'Could not read line ', count_lines, ' in file '//trim(adjustl(File_name))
         print*, trim(adjustl(Error_descript))
         goto 3417
      endif
      !matter%Atoms(Scell(NSC)%MDatoms(i)%KOA)%Ma
   enddo

   ! All atoms distribution (in the super-cell):
   j = 0 ! for the beginning
   ncellx = matter%cell_x
   ncelly = matter%cell_y
   ncellz = matter%cell_z
   do nx = 0, ncellx-1
      do ny = 0, ncelly-1
         do nz = 0, ncellz-1
            do k = 1,Na	! number of atoms in the unit cell is FIXED
               j = j + 1
               do i=1,3
                  if (i .EQ. 1) then
                     a = REAL(nx)*1.0d0
                     l2 = REAL(ncellx)
                  endif
                  if (i .EQ. 2) then
                     a = REAL(ny)*1.0d0
                     l2 =  REAL(ncelly)
                  endif
                  if (i .EQ. 3) then
                     a = REAL(nz)*1.0d0
                     l2 =  REAL(ncellz)
                  endif
                  
                  ! Add a tiny shift to coordinates of replicated atoms:
                  call random_number(RN)
                  if (RN > 0.5d0) then
                     coord_shift = epsylon*RN
                  else
                     coord_shift = -epsylon*RN
                  endif
                  
                  Scell(SCN)%MDatoms(j)%S(i) = (Relcoat(i,k) + a + coord_shift)/l2  ! relative coordinates of an atom
                  Scell(SCN)%MDatoms(j)%KOA = Scell(SCN)%MDatoms(k)%KOA ! kind of atom
               enddo ! i
            enddo ! k
         enddo ! nz
      enddo ! ny
   enddo ! nx
   deallocate(Relcoat)

   call check_periodic_boundaries(matter, Scell, SCN)   ! module "Atomic_tools"
!    call Coordinates_rel_to_abs(Scell, SCN)	! from the module "Atomic_tools"

   do j = 1, Scell(SCN)%Na
      Scell(SCN)%MDatoms(j)%R0(:) = Scell(SCN)%MDatoms(j)%R(:)	! coords at "previous" time step
      Scell(SCN)%MDatoms(j)%S0(:) = Scell(SCN)%MDatoms(j)%S(:)	! relative coords at "previous" time step
!       write(*,'(i3,i2,f,f,f,f,f,f)') j, Scell(SCN)%MDatoms(j)%KOA, Scell(SCN)%MDatoms(j)%R(:), Scell(SCN)%MDatoms(j)%S(:)
   enddo ! j
!    pause 'INITIAL CONDITIONS'

   ! If we want to shift all atoms:
   ! call Shift_all_atoms(matter, atoms, 0.25d0, 0.25d0, 0.25d0) ! from the module "Atomic_tools"
3417 continue

end subroutine set_initial_coords


subroutine set_initial_velocities(matter, Scell, NSC, atoms, numpar, allow_rotation)
   type(solid), intent(inout) :: matter	! materil parameters
   type(Super_cell), dimension(:), intent(inout) :: Scell ! suoer-cell with all the atoms inside
   integer, intent(in) :: NSC ! number of the super-cell
   type(Atom), dimension(:), intent(inout) :: atoms	! array of atoms in the supercell
   type(Numerics_param), intent(in) :: numpar	! numerical parameters
   logical, intent(in) :: allow_rotation ! remove angular momentum or not?
   !-------------------------------------------------------
   real(8) :: xr, SCVol, Xcm, Ycm, Zcm, vx, vy, vz, BigL(3), BigI(3,3), BigIinv(3,3)
   real(8) :: x0(3),r1, v0(3), rxv(3), omeg(3), Na, V_temp, Mass
   real(8), dimension(:), allocatable :: indices ! working array of indices
   integer i, j

   ! Set random velocities for all atoms:
   do i = 1,Scell(NSC)%Na ! velociteis of all atoms
      Mass = matter%Atoms(Scell(NSC)%MDatoms(i)%KOA)%Ma
      ! Get initial velocity
      call Get_random_velocity(Scell(NSC)%TaeV, Mass, atoms(i)%V(1), atoms(i)%V(2), atoms(i)%V(3), 2) ! module "Atomic_tools"
   enddo

   ! Set initial velocities for the super-cell vectors:
   Scell(NSC)%Vsupce = 0.0d0 ! this part of energy is in atoms at first, so let them relax!
   Scell(NSC)%Vsupce0 = Scell(NSC)%Vsupce ! Derivatives of Super-cell vectors (velocities) on last time-step

   !AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
   ! Find unconnected fragments of which the material is constructed (can be one piece too):
   call get_fragments_indices(Scell, NSC, numpar, atoms, matter, indices) ! module "Atomic_tools"
   
!     print*, 'indices', indices
!     pause
   
   !AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
   ! Eliminate initial angular momentum of the super-cell and each fragment inside:
   
!    do i = 1,Scell(NSC)%Na ! velociteis of all atoms
!       print*, 'set_initial_velocities 0', atoms(i)%S(:), atoms(i)%R(:)
!    enddo
   
   if (.not.allow_rotation) call remove_angular_momentum(NSC, Scell, matter, atoms, indices) ! module "Atomic_tools"
    !AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
   ! Eliminate total momentum of the center-of-mass and each fragment inside:
   call remove_momentum(Scell, NSC, matter, atoms, indices) ! module "Atomic_tools"
   
!    do i = 1,Scell(NSC)%Na ! velociteis of all atoms
!       print*, 'set_initial_velocities 1', atoms(i)%S(:), atoms(i)%R(:)
!    enddo
   
   ! Set relative velocities according to the new absolute ones:
   call velocities_abs_to_rel(Scell, NSC)
end subroutine set_initial_velocities



subroutine get_supercell_vectors(FN, File_name, Scell, SCN, which_one, matter, Err, ind)
   integer, intent(in) :: FN, which_one, SCN ! file number; type of file to read from (2=unit-cell, 1=super-cell); number of supercell
   character(*), intent(in) :: File_name ! file with the super-cell parameters
   type(Super_cell), dimension(:), intent(inout) :: Scell ! suoer-cell with all the atoms inside
   type(Solid), intent(in) :: matter	! all material parameters
   type(Error_handling), intent(inout) :: Err	! error save
   integer, intent(in), optional :: ind     ! index into which variable to save the data
   !=========================================
   real(8), dimension(3,3) :: unit_cell
   real(8), dimension(3) :: temp_vec
   integer Reason, count_lines, i
   character(200) Error_descript
   logical read_well
   count_lines = 0
   select case (which_one)
   case (1) ! super-cell
      do i = 1,15 ! read supercell data:
      select case (i)
      case (1:3)   ! supercell
         if (present(ind)) then
            if (ind == 1) then   ! to read this index or not
               read(FN,*,IOSTAT=Reason) temp_vec
               Scell(SCN)%supce(i,:) =  temp_vec
            else
               read(FN,*,IOSTAT=Reason) ! do not read this index
            endif
         else
            read(FN,*,IOSTAT=Reason) temp_vec
            Scell(SCN)%supce(i,:) =  temp_vec
         endif
         call read_file(Reason, count_lines, read_well)
         if (.not. read_well) then
            write(Error_descript,'(a,i3,a,$)') 'Could not read line ', count_lines, ' in file '//trim(adjustl(File_name))
            call Save_error_details(Err, 3, Error_descript)
            print*, trim(adjustl(Error_descript))
            goto 3417
         endif
      case (5:7)   ! supercell0
         if (present(ind)) then
            if (ind == 0) then
               read(FN,*,IOSTAT=Reason) temp_vec
               Scell(SCN)%supce0(i-4,:) = temp_vec
            else
               read(FN,*,IOSTAT=Reason) ! do not read this index
            endif
         else
            read(FN,*,IOSTAT=Reason) temp_vec
            Scell(SCN)%supce0(i-4,:) = temp_vec
         endif
         call read_file(Reason, count_lines, read_well)
         if (.not. read_well) then
            write(Error_descript,'(a,i3,a,$)') 'Could not read line ', count_lines, ' in file '//trim(adjustl(File_name))
            call Save_error_details(Err, 3, Error_descript)
            print*, trim(adjustl(Error_descript))
            goto 3417
         endif
      case (9:11)  ! supce vel
         if (present(ind)) then
            if (ind == 1) then
               read(FN,*,IOSTAT=Reason) temp_vec
               Scell(SCN)%Vsupce(i-8,:) = temp_vec
            else
               read(FN,*,IOSTAT=Reason) ! do not read this index
            endif
         else
            read(FN,*,IOSTAT=Reason) temp_vec
            Scell(SCN)%Vsupce(i-8,:) = temp_vec
         endif
         call read_file(Reason, count_lines, read_well)
         if (.not. read_well) then
            write(Error_descript,'(a,i3,a,$)') 'Could not read line ', count_lines, ' in file '//trim(adjustl(File_name))
            call Save_error_details(Err, 3, Error_descript)
            print*, trim(adjustl(Error_descript))
            goto 3417
         endif
      case (13:15)  ! supce vel0
       if (present(ind)) then
            if (ind == 0) then
               read(FN,*,IOSTAT=Reason) temp_vec
               Scell(SCN)%Vsupce0(i-12,:) = temp_vec
            else
               read(FN,*,IOSTAT=Reason) ! do not read this index
            endif
         else
            read(FN,*,IOSTAT=Reason) temp_vec
            Scell(SCN)%Vsupce0(i-12,:) = temp_vec
         endif
         call read_file(Reason, count_lines, read_well)
         if (.not. read_well) then
            write(Error_descript,'(a,i3,a,$)') 'Could not read line ', count_lines, ' in file '//trim(adjustl(File_name))
            call Save_error_details(Err, 3, Error_descript)
            print*, trim(adjustl(Error_descript))
            goto 3417
         endif
      case (4,8,12)
         read(FN,*,IOSTAT=Reason) ! skip the lines separating the data sets
         call read_file(Reason, count_lines, read_well)
         if (.not. read_well) then
            write(Error_descript,'(a,i3,a,$)') 'Could not read line ', count_lines, ' in file '//trim(adjustl(File_name))
            call Save_error_details(Err, 3, Error_descript)
            print*, trim(adjustl(Error_descript))
            goto 3417
         endif
      end select
      enddo
   case default ! unit-cell
      read(FN,*,IOSTAT=Reason) unit_cell
      call read_file(Reason, count_lines, read_well)
      if (.not. read_well) then
         write(Error_descript,'(a,i3,a,$)') 'Could not read line ', count_lines, ' in file '//trim(adjustl(File_name))
         call Save_error_details(Err, 3, Error_descript)
         print*, trim(adjustl(Error_descript))
         goto 3417
      endif
!       Scell(SCN)%supce(:,1) = matter%cell_x*unit_cell(:,1)	! [A] length of super-cell X
!       Scell(SCN)%supce(:,2) = matter%cell_y*unit_cell(:,2)	! [A] length of super-cell Y
!       Scell(SCN)%supce(:,3) = matter%cell_z*unit_cell(:,3)	! [A] length of super-cell Z
      Scell(SCN)%supce(1,:) = matter%cell_x*unit_cell(1,:)	! [A] length of super-cell X
      Scell(SCN)%supce(2,:) = matter%cell_y*unit_cell(2,:)	! [A] length of super-cell Y
      Scell(SCN)%supce(3,:) = matter%cell_z*unit_cell(3,:)	! [A] length of super-cell Z 
      Scell(SCN)%supce0 = Scell(SCN)%supce	! [A] length of super-cell on the previous time-step
      Scell(SCN)%Vsupce = 0.0d0  ! initial velocity is 0
      Scell(SCN)%Vsupce0 = 0.0d0 ! initial velocity is 0
   end select
   
    if (present(ind)) then  ! if we define two phases
       if (ind == 1) then
          Scell(SCN)%SCforce%rep = 0.0d0
          Scell(SCN)%SCforce%att = 0.0d0
          Scell(SCN)%SCforce%total = 0.0d0
          call Det_3x3(Scell(SCN)%supce, Scell(SCN)%V) ! finding initial volume of the super-cell, module "Algebra_tools"
          call Reciproc(Scell(SCN)%supce, Scell(SCN)%k_supce) ! create reciprocal super-cell, module "Algebra_tools"
          Scell(SCN)%supce_eq = Scell(SCN)%supce	! [A] equilibrium lengths of super-cell
       else
          ! do nothing for this index
       endif
    else    ! if we define one supercell
       Scell(SCN)%SCforce%rep = 0.0d0
       Scell(SCN)%SCforce%att = 0.0d0
       Scell(SCN)%SCforce%total = 0.0d0
       call Det_3x3(Scell(SCN)%supce, Scell(SCN)%V) ! finding initial volume of the super-cell, module "Algebra_tools"
       call Reciproc(Scell(SCN)%supce, Scell(SCN)%k_supce) ! create reciprocal super-cell, module "Algebra_tools"
       Scell(SCN)%supce_eq = Scell(SCN)%supce	! [A] equilibrium lengths of super-cell
    endif

3417 continue
end subroutine get_supercell_vectors



END MODULE Initial_configuration

!{\src2tex{textfont=tt}}
!!****f* ABINIT/cg_rotate
!! NAME
!!  cg_rotate
!!
!! FUNCTION
!!
!! COPYRIGHT
!! Copyright (C) 2014-2018 ABINIT group (MG)
!! This file is distributed under the terms of the
!! GNU General Public License, see ~abinit/COPYING
!! or http://www.gnu.org/copyleft/gpl.txt .
!! For the initials of contributors, see ~abinit/doc/developers/contributors.txt .
!!
!! INPUTS
!!  isym
!!  itimrev
!!  nspinor
!!  ndat
!!  npw1,npw2
!!  istwf1,istwf2
!!  cryst<crystal_t>
!!  shiftg(3)
!!  kg1(3,npw1), kg2(3,npw2)
!!  work_ngfft(18)
!!  kpt1(3)
!!  cg1(2,npw1,nspinor,ndat)
!!
!! OUTPUT
!!  cg2(2,npw2,nspinor,ndat)
!!  work(2,work_ngfft(4),work_ngfft(5),work_ngfft(6)) !*ndat),
!!
!! PARENTS
!!      m_phgamma,m_sigmaph,m_wfk
!!
!! NOTES
!!  Inspired to wfconv.
!!
!! CHILDREN
!!      getph,getspinrot,mati3inv,ph1d3d,sphere
!!
!! SOURCE

#if defined HAVE_CONFIG_H
#include "config.h"
#endif

#include "abi_common.h"

subroutine cg_rotate(cryst,kpt1,isym,itimrev,shiftg,nspinor,ndat,&
  npw1,kg1,npw2,kg2,istwf1,istwf2,cg1,cg2,work_ngfft,work)

 use defs_basis
 use m_errors
 use m_profiling_abi

 use m_crystal,   only : crystal_t
 use m_fftcore,   only : sphere
 use m_kg,        only : ph1d3d, getph

!This section has been created automatically by the script Abilint (TD).
!Do not modify the following lines by hand.
#undef ABI_FUNC
#define ABI_FUNC 'cg_rotate'
 use interfaces_32_util
!End of the abilint section

 implicit none

!Arguments ------------------------------------
!scalars
 integer,intent(in) :: isym,itimrev,nspinor,ndat,npw1,npw2,istwf1,istwf2
 type(crystal_t),intent(in) :: cryst
!arrays
 integer,intent(in) :: shiftg(3),kg1(3,npw1),kg2(3,npw2)
 integer,intent(in) :: work_ngfft(18)
 real(dp),intent(in) :: kpt1(3)
 real(dp),intent(in) :: cg1(2,npw1,nspinor,ndat)
 real(dp),intent(out) :: cg2(2,npw2,nspinor,ndat)
 real(dp),intent(out) :: work(2,work_ngfft(4),work_ngfft(5),work_ngfft(6)) !*ndat) for threads?

!Local variables ------------------------------
!scalars
 integer,parameter :: tobox=1,tosph=-1,me_g0=1
 integer :: n1,n2,n3,n4,n5,n6,ipw,idat,isp
 real(dp) :: arg,ar,ai,bi,br,spinrots,spinrotx,spinroty,spinrotz
 logical :: have_phase
!arrays
 integer,parameter :: no_shift(3)=0,atindx(1)=1
 integer :: symm(3,3),symrel_conv(3,3)
 real(dp) :: phktnons(2,1),tnons_conv(3),spinrot(4)
 real(dp),allocatable :: phase1d(:,:),phase3d(:,:),wavef1(:,:)

!************************************************************************

 n1=work_ngfft(1); n2=work_ngfft(2); n3=work_ngfft(3)
 n4=work_ngfft(4); n5=work_ngfft(5); n6=work_ngfft(6)

 symrel_conv = cryst%symrel(:,:,isym)
 call mati3inv(symrel_conv, symm)
 tnons_conv = cryst%tnons(:,isym) !
 have_phase = sum(tnons_conv**2) > tol8

 ! Compute rotation in spinor space
 if (nspinor == 2) call getspinrot(cryst%rprimd,spinrot,symrel_conv)
 if (itimrev == 1) symm = -symm

 ! Need to compute phase factors associated with nonsymmorphic translations?
 if (have_phase) then
   ABI_MALLOC(phase3d,(2,npw1))
   ABI_MALLOC(phase1d,(2,(2*n1+1)+(2*n2+1)+(2*n3+1)))
   ! Although the routine getph is originally written for atomic phase factors, it does precisely what we want
   call getph(atindx,1,n1,n2,n3,phase1d,tnons_conv)

   arg = two_pi*(kpt1(1)*tnons_conv(1)+ kpt1(2)*tnons_conv(2)+ kpt1(3)*tnons_conv(3))
   phktnons(1,1)=cos(arg)
   phktnons(2,1)=sin(arg)
   ! Convert 1D phase factors to 3D phase factors exp(i 2 pi (k+G).tnons )
   call ph1d3d(1,1,kg1,1,1,npw1,n1,n2,n3,phktnons,phase1d,phase3d)
 end if

 ABI_MALLOC(wavef1, (2,npw1))

 do idat=1,ndat

   do isp=1,nspinor
     wavef1 = cg1(:,:,isp,idat)

     if (have_phase) then
       ! Multiply by phase factors due to nonsymmorphic translations.
       do ipw=1,npw1
         ar = phase3d(1,ipw)*wavef1(1,ipw)-phase3d(2,ipw)*wavef1(2,ipw)
         ai = phase3d(2,ipw)*wavef1(1,ipw)+phase3d(1,ipw)*wavef1(2,ipw)
         wavef1(1,ipw)=ar
         wavef1(2,ipw)=ai
       end do
     end if

     ! Take into account time-reversal symmetry, if needed, in the scalar case
     if (itimrev == 1 .and. nspinor == 1) wavef1(2,:npw1) = -wavef1(2,:npw1)

     ! Insert wavef1 in work array.
     call sphere(wavef1,1,npw1,work,n1,n2,n3,n4,n5,n6,kg1,istwf1,tobox,me_g0,no_shift,identity_3d,one)

     ! Apply rotation and extract data.
     call sphere(cg2(:,:,isp,idat),1,npw2,work,n1,n2,n3,n4,n5,n6,kg2,istwf2,tosph,me_g0,shiftg,symm,one)
   end do ! isp

   if (nspinor == 2) then
     if (itimrev == 1) then
       ! Take care of time-reversal symmetry, if needed
       ! Exchange spin-up and spin-down. Make complex conjugate of one component,
       ! and change sign of other component
       do ipw=1,npw2
         ! Here, change sign of real part
         ar = -cg2(1,ipw,1,idat)
         ai =  cg2(2,ipw,1,idat)
         ! Here, change sign of imaginary part
         cg2(1,ipw,1,idat) =  cg2(1,ipw,2,idat)
         cg2(2,ipw,1,idat) = -cg2(2,ipw,2,idat)
         cg2(1,ipw,2,idat) = ar
         cg2(2,ipw,2,idat) = ai
       end do
     end if ! itimrev==1

     ! Rotation in spinor space (see also wfconv)
     spinrots = spinrot(1)
     spinrotx = spinrot(2)
     spinroty = spinrot(3)
     spinrotz = spinrot(4)
     do ipw=1,npw2
       ar = cg2(1,ipw,1,idat)
       ai = cg2(2,ipw,1,idat)
       br = cg2(1,ipw,2,idat)
       bi = cg2(2,ipw,2,idat)
       cg2(1,ipw,1,idat) =  spinrots*ar-spinrotz*ai +spinroty*br-spinrotx*bi
       cg2(2,ipw,1,idat) =  spinrots*ai+spinrotz*ar +spinroty*bi+spinrotx*br
       cg2(1,ipw,2,idat) = -spinroty*ar-spinrotx*ai +spinrots*br+spinrotz*bi
       cg2(2,ipw,2,idat) = -spinroty*ai+spinrotx*ar +spinrots*bi-spinrotz*br
     end do
   end if

 end do ! idat

 ABI_FREE(wavef1)

 if (have_phase) then
   ABI_FREE(phase3d)
   ABI_FREE(phase1d)
 end if

end subroutine cg_rotate
!!***

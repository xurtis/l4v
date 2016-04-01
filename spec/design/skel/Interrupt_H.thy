(*
 * Copyright 2014, General Dynamics C4 Systems
 *
 * This software may be distributed and modified according to the terms of
 * the GNU General Public License version 2. Note that NO WARRANTY is provided.
 * See "LICENSE_GPLv2.txt" for details.
 *
 * @TAG(GD_GPL)
 *)

theory Interrupt_H
imports
  RetypeDecls_H
  "./$L4V_ARCH/ArchInterrupt_H"
  Notification_H
  CNode_H
  KI_Decls_H
  InterruptDecls_H
begin

unqualify_consts (in Arch)
  maxIRQ
  minIRQ
  maskInterrupt
  ackInterrupt
  resetTimer
  debugPrint

#INCLUDE_HASKELL_PREPARSE SEL4/Object/Structures.lhs
#INCLUDE_HASKELL SEL4/Object/Interrupt.lhs bodies_only

end

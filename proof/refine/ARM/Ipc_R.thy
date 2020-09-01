(*
 * Copyright 2014, General Dynamics C4 Systems
 *
 * SPDX-License-Identifier: GPL-2.0-only
 *)

theory Ipc_R
imports Finalise_R
begin

context begin interpretation Arch . (*FIXME: arch_split*)

lemmas lookup_slot_wrapper_defs'[simp] =
   lookupSourceSlot_def lookupTargetSlot_def lookupPivotSlot_def

lemma get_mi_corres: "corres ((=) \<circ> message_info_map)
                      (tcb_at t) (tcb_at' t)
                      (get_message_info t) (getMessageInfo t)"
  apply (rule corres_guard_imp)
    apply (unfold get_message_info_def getMessageInfo_def fun_app_def)
    apply (simp add: ARM_H.msgInfoRegister_def
             ARM.msgInfoRegister_def ARM_A.msg_info_register_def)
    apply (rule corres_split_eqr [OF _ user_getreg_corres])
       apply (rule corres_trivial, simp add: message_info_from_data_eqv)
      apply (wp | simp)+
  done


lemma get_mi_inv'[wp]: "\<lbrace>I\<rbrace> getMessageInfo a \<lbrace>\<lambda>x. I\<rbrace>"
  by (simp add: getMessageInfo_def, wp)

definition
  "get_send_cap_relation rv rv' \<equiv>
   (case rv of Some (c, cptr) \<Rightarrow> (\<exists>c' cptr'. rv' = Some (c', cptr') \<and>
                                            cte_map cptr = cptr' \<and>
                                            cap_relation c c')
             | None \<Rightarrow> rv' = None)"

lemma cap_relation_mask:
  "\<lbrakk> cap_relation c c'; msk' = rights_mask_map msk \<rbrakk> \<Longrightarrow>
  cap_relation (mask_cap msk c) (maskCapRights msk' c')"
  by simp

lemma lsfco_cte_at':
  "\<lbrace>valid_objs' and valid_cap' cap\<rbrace>
  lookupSlotForCNodeOp f cap idx depth
  \<lbrace>\<lambda>rv. cte_at' rv\<rbrace>, -"
  apply (simp add: lookupSlotForCNodeOp_def)
  apply (rule conjI)
   prefer 2
   apply clarsimp
   apply (wp)
  apply (clarsimp simp: split_def unlessE_def
             split del: if_split)
  apply (wp hoare_drop_imps throwE_R)
  done

declare unifyFailure_wp [wp]

(* FIXME: move *)
lemma unifyFailure_wp_E [wp]:
  "\<lbrace>P\<rbrace> f -, \<lbrace>\<lambda>_. E\<rbrace> \<Longrightarrow> \<lbrace>P\<rbrace> unifyFailure f -, \<lbrace>\<lambda>_. E\<rbrace>"
  unfolding validE_E_def
  by (erule unifyFailure_wp)+

(* FIXME: move *)
lemma unifyFailure_wp2 [wp]:
  assumes x: "\<lbrace>P\<rbrace> f \<lbrace>\<lambda>_. Q\<rbrace>"
  shows      "\<lbrace>P\<rbrace> unifyFailure f \<lbrace>\<lambda>_. Q\<rbrace>"
  by (wp x, simp)

definition
  ct_relation :: "captransfer \<Rightarrow> cap_transfer \<Rightarrow> bool"
where
 "ct_relation ct ct' \<equiv>
    ct_receive_root ct = to_bl (ctReceiveRoot ct')
  \<and> ct_receive_index ct = to_bl (ctReceiveIndex ct')
  \<and> ctReceiveDepth ct' = unat (ct_receive_depth ct)"

(* MOVE *)
lemma valid_ipc_buffer_ptr_aligned_2:
  "\<lbrakk>valid_ipc_buffer_ptr' a s;  is_aligned y 2 \<rbrakk> \<Longrightarrow> is_aligned (a + y) 2"
  unfolding valid_ipc_buffer_ptr'_def
  apply clarsimp
  apply (erule (1) aligned_add_aligned)
  apply (simp add: msg_align_bits)
  done

(* MOVE *)
lemma valid_ipc_buffer_ptr'D2:
  "\<lbrakk>valid_ipc_buffer_ptr' a s; y < max_ipc_words * 4; is_aligned y 2\<rbrakk> \<Longrightarrow> typ_at' UserDataT (a + y && ~~ mask pageBits) s"
  unfolding valid_ipc_buffer_ptr'_def
  apply clarsimp
  apply (subgoal_tac "(a + y) && ~~ mask pageBits = a  && ~~ mask pageBits")
   apply simp
  apply (rule mask_out_first_mask_some [where n = msg_align_bits])
   apply (erule is_aligned_add_helper [THEN conjunct2])
   apply (erule order_less_le_trans)
   apply (simp add: msg_align_bits max_ipc_words )
  apply simp
  done

lemma load_ct_corres:
  "corres ct_relation \<top> (valid_ipc_buffer_ptr' buffer) (load_cap_transfer buffer) (loadCapTransfer buffer)"
  apply (simp add: load_cap_transfer_def loadCapTransfer_def
                   captransfer_from_words_def
                   capTransferDataSize_def capTransferFromWords_def
                   msgExtraCapBits_def word_size add.commute add.left_commute
                   msg_max_length_def msg_max_extra_caps_def word_size_def
                   msgMaxLength_def msgMaxExtraCaps_def msgLengthBits_def wordSize_def wordBits_def
              del: upt.simps)
  apply (rule corres_guard_imp)
    apply (rule corres_split [OF _ load_word_corres])
      apply (rule corres_split [OF _ load_word_corres])
        apply (rule corres_split [OF _ load_word_corres])
          apply (rule_tac P=\<top> and P'=\<top> in corres_inst)
          apply (clarsimp simp: ct_relation_def)
         apply (wp no_irq_loadWord)+
   apply simp
  apply (simp add: conj_comms)
  apply safe
       apply (erule valid_ipc_buffer_ptr_aligned_2, simp add: is_aligned_def)+
    apply (erule valid_ipc_buffer_ptr'D2, simp add: max_ipc_words, simp add: is_aligned_def)+
  done

lemma get_recv_slot_corres:
  "corres (\<lambda>xs ys. ys = map cte_map xs)
    (tcb_at receiver and valid_objs and pspace_aligned)
    (tcb_at' receiver and valid_objs' and pspace_aligned' and pspace_distinct' and
     case_option \<top> valid_ipc_buffer_ptr' recv_buf)
    (get_receive_slots receiver recv_buf)
    (getReceiveSlots receiver recv_buf)"
  apply (cases recv_buf)
   apply (simp add: getReceiveSlots_def)
  apply (simp add: getReceiveSlots_def split_def)
  apply (rule corres_guard_imp)
    apply (rule corres_split [OF _ load_ct_corres])
      apply (rule corres_empty_on_failure)
      apply (rule corres_splitEE)
         prefer 2
         apply (rule corres_unify_failure)
          apply (rule lookup_cap_corres)
          apply (simp add: ct_relation_def)
         apply simp
        apply (rule corres_splitEE)
           prefer 2
           apply (rule corres_unify_failure)
            apply (simp add: ct_relation_def)
            apply (erule lsfc_corres [OF _ refl])
           apply simp
          apply (simp add: split_def liftE_bindE unlessE_whenE)
          apply (rule corres_split [OF _ get_cap_corres])
            apply (rule corres_split_norE)
               apply (rule corres_trivial, simp add: returnOk_def)
              apply (rule corres_whenE)
                apply (case_tac cap, auto)[1]
               apply (rule corres_trivial, simp)
              apply simp
             apply (wp lookup_cap_valid lookup_cap_valid' lsfco_cte_at | simp)+
  done

lemma get_recv_slot_inv'[wp]:
  "\<lbrace> P \<rbrace> getReceiveSlots receiver buf \<lbrace>\<lambda>rv'. P \<rbrace>"
  apply (case_tac buf)
   apply (simp add: getReceiveSlots_def)
  apply (simp add: getReceiveSlots_def
                   split_def unlessE_def)
  apply (wp | simp)+
  done

lemma get_rs_cte_at'[wp]:
  "\<lbrace>\<top>\<rbrace>
   getReceiveSlots receiver recv_buf
   \<lbrace>\<lambda>rv s. \<forall>x \<in> set rv. cte_wp_at' (\<lambda>c. cteCap c = capability.NullCap) x s\<rbrace>"
  apply (cases recv_buf)
   apply (simp add: getReceiveSlots_def)
   apply (wp,simp)
  apply (clarsimp simp add: getReceiveSlots_def
                            split_def whenE_def unlessE_whenE)
  apply wp
     apply simp
     apply (rule getCTE_wp)
    apply (simp add: cte_wp_at_ctes_of cong: conj_cong)
    apply wp+
  apply simp
  done

lemma get_rs_real_cte_at'[wp]:
  "\<lbrace>valid_objs'\<rbrace>
   getReceiveSlots receiver recv_buf
   \<lbrace>\<lambda>rv s. \<forall>x \<in> set rv. real_cte_at' x s\<rbrace>"
  apply (cases recv_buf)
   apply (simp add: getReceiveSlots_def)
   apply (wp,simp)
  apply (clarsimp simp add: getReceiveSlots_def
                            split_def whenE_def unlessE_whenE)
  apply wp
     apply simp
     apply (wp hoare_drop_imps)[1]
    apply simp
    apply (wp lookup_cap_valid')+
  apply simp
  done

declare word_div_1 [simp]
declare word_minus_one_le [simp]
declare word32_minus_one_le [simp]

lemma load_word_offs_corres':
  "\<lbrakk> y < unat max_ipc_words; y' = of_nat y * 4 \<rbrakk> \<Longrightarrow>
  corres (=) \<top> (valid_ipc_buffer_ptr' a) (load_word_offs a y) (loadWordUser (a + y'))"
  apply simp
  apply (erule load_word_offs_corres)
  done

declare loadWordUser_inv [wp]

lemma getExtraCptrs_inv[wp]:
  "\<lbrace>P\<rbrace> getExtraCPtrs buf mi \<lbrace>\<lambda>rv. P\<rbrace>"
  apply (cases mi, cases buf, simp_all add: getExtraCPtrs_def)
  apply (wp dmo_inv' mapM_wp' loadWord_inv)
  done

lemma badge_derived_mask [simp]:
  "badge_derived' (maskCapRights R c) c' = badge_derived' c c'"
  by (simp add: badge_derived'_def)

declare derived'_not_Null [simp]

lemma maskCapRights_vsCapRef[simp]:
  "vsCapRef (maskCapRights msk cap) = vsCapRef cap"
  unfolding vsCapRef_def
  apply (cases cap, simp_all add: maskCapRights_def isCap_simps Let_def)
  apply (rename_tac arch_capability)
  apply (case_tac arch_capability;
         simp add: maskCapRights_def ARM_H.maskCapRights_def isCap_simps Let_def)
  done

lemma corres_set_extra_badge:
  "b' = b \<Longrightarrow>
  corres dc (in_user_frame buffer)
         (valid_ipc_buffer_ptr' buffer and
          (\<lambda>_. msg_max_length + 2 + n < unat max_ipc_words))
         (set_extra_badge buffer b n) (setExtraBadge buffer b' n)"
  apply (rule corres_gen_asm2)
  apply (drule store_word_offs_corres [where a=buffer and w=b])
  apply (simp add: set_extra_badge_def setExtraBadge_def buffer_cptr_index_def
                   bufferCPtrOffset_def Let_def)
  apply (simp add: word_size word_size_def wordSize_def wordBits_def
                   bufferCPtrOffset_def buffer_cptr_index_def msgMaxLength_def
                   msg_max_length_def msgLengthBits_def store_word_offs_def
                   add.commute add.left_commute)
  done

crunch typ_at': setExtraBadge "\<lambda>s. P (typ_at' T p s)"
lemmas setExtraBadge_typ_ats' [wp] = typ_at_lifts [OF setExtraBadge_typ_at']
crunch valid_pspace' [wp]: setExtraBadge valid_pspace'
crunch cte_wp_at' [wp]: setExtraBadge "cte_wp_at' P p"
crunch ipc_buffer' [wp]: setExtraBadge "valid_ipc_buffer_ptr' buffer"

crunch inv'[wp]: getExtraCPtr P (wp: dmo_inv' loadWord_inv)

lemmas unifyFailure_discard2
    = corres_injection[OF id_injection unifyFailure_injection, simplified]

lemma deriveCap_not_null:
  "\<lbrace>\<top>\<rbrace> deriveCap slot cap \<lbrace>\<lambda>rv. K (rv \<noteq> NullCap \<longrightarrow> cap \<noteq> NullCap)\<rbrace>,-"
  apply (simp add: deriveCap_def split del: if_split)
  apply (case_tac cap)
          apply (simp_all add: Let_def isCap_simps)
  apply wp
  apply simp
  done

lemma deriveCap_derived_foo:
  "\<lbrace>\<lambda>s. \<forall>cap'. (cte_wp_at' (\<lambda>cte. badge_derived' cap (cteCap cte)
                     \<and> capASID cap = capASID (cteCap cte) \<and> cap_asid_base' cap = cap_asid_base' (cteCap cte)
                     \<and> cap_vptr' cap = cap_vptr' (cteCap cte)) slot s
              \<and> valid_objs' s \<and> cap' \<noteq> NullCap \<longrightarrow> cte_wp_at' (is_derived' (ctes_of s) slot cap' \<circ> cteCap) slot s)
        \<and> (cte_wp_at' (untyped_derived_eq cap \<circ> cteCap) slot s
            \<longrightarrow> cte_wp_at' (untyped_derived_eq cap' \<circ> cteCap) slot s)
        \<and> (s \<turnstile>' cap \<longrightarrow> s \<turnstile>' cap') \<and> (cap' \<noteq> NullCap \<longrightarrow> cap \<noteq> NullCap) \<longrightarrow> Q cap' s\<rbrace>
    deriveCap slot cap \<lbrace>Q\<rbrace>,-"
  using deriveCap_derived[where slot=slot and c'=cap] deriveCap_valid[where slot=slot and c=cap]
        deriveCap_untyped_derived[where slot=slot and c'=cap] deriveCap_not_null[where slot=slot and cap=cap]
  apply (clarsimp simp: validE_R_def validE_def valid_def split: sum.split)
  apply (frule in_inv_by_hoareD[OF deriveCap_inv])
  apply (clarsimp simp: o_def)
  apply (drule spec, erule mp)
  apply safe
     apply fastforce
    apply (drule spec, drule(1) mp)
    apply fastforce
   apply (drule spec, drule(1) mp)
   apply fastforce
  apply (drule spec, drule(1) bspec, simp)
  done

lemma valid_mdb_untyped_incD':
  "valid_mdb' s \<Longrightarrow> untyped_inc' (ctes_of s)"
  by (simp add: valid_mdb'_def valid_mdb_ctes_def)

lemma cteInsert_cte_wp_at:
  "\<lbrace>\<lambda>s. cte_wp_at' (\<lambda>c. is_derived' (ctes_of s) src cap (cteCap c)) src s
       \<and> valid_mdb' s \<and> valid_objs' s
       \<and> (if p = dest then P cap
            else cte_wp_at' (\<lambda>c. P (maskedAsFull (cteCap c) cap)) p s)\<rbrace>
    cteInsert cap src dest
   \<lbrace>\<lambda>uu. cte_wp_at' (\<lambda>c. P (cteCap c)) p\<rbrace>"
  apply (simp add: cteInsert_def)
  apply (wp updateMDB_weak_cte_wp_at updateCap_cte_wp_at_cases getCTE_wp static_imp_wp
         | clarsimp simp: comp_def
         | unfold setUntypedCapAsFull_def)+
  apply (drule cte_at_cte_wp_atD)
  apply (elim exE)
  apply (rule_tac x=cte in exI)
  apply clarsimp
  apply (drule cte_at_cte_wp_atD)
  apply (elim exE)
  apply (rule_tac x=ctea in exI)
  apply clarsimp
  apply (cases "p=dest")
   apply (clarsimp simp: cte_wp_at'_def)
  apply (cases "p=src")
   apply clarsimp
   apply (intro conjI impI)
    apply ((clarsimp simp: cte_wp_at'_def maskedAsFull_def split: if_split_asm)+)[2]
  apply clarsimp
  apply (rule conjI)
   apply (clarsimp simp: maskedAsFull_def cte_wp_at_ctes_of split:if_split_asm)
   apply (erule disjE) prefer 2 apply simp
   apply (clarsimp simp: is_derived'_def isCap_simps)
   apply (drule valid_mdb_untyped_incD')
   apply (case_tac cte, case_tac cteb, clarsimp)
   apply (drule untyped_incD', (simp add: isCap_simps)+)
   apply (frule(1) ctes_of_valid'[where p = p])
   apply (clarsimp simp:valid_cap'_def capAligned_def split:if_splits)
    apply (drule_tac y ="of_nat fb"  in word_plus_mono_right[OF _  is_aligned_no_overflow',rotated])
      apply simp+
     apply (rule word_of_nat_less)
     apply simp
    apply (simp add:p_assoc_help)
   apply (simp add: max_free_index_def)
  apply (clarsimp simp: maskedAsFull_def is_derived'_def badge_derived'_def
                        isCap_simps capMasterCap_def cte_wp_at_ctes_of
                  split: if_split_asm capability.splits)
  done

lemma cteInsert_weak_cte_wp_at3:
  assumes imp:"\<And>c. P c \<Longrightarrow> \<not> isUntypedCap c"
  shows " \<lbrace>\<lambda>s. if p = dest then P cap
            else cte_wp_at' (\<lambda>c. P (cteCap c)) p s\<rbrace>
    cteInsert cap src dest
   \<lbrace>\<lambda>uu. cte_wp_at' (\<lambda>c. P (cteCap c)) p\<rbrace>"
  by (wp updateMDB_weak_cte_wp_at updateCap_cte_wp_at_cases getCTE_wp' static_imp_wp
         | clarsimp simp: comp_def cteInsert_def
         | unfold setUntypedCapAsFull_def
         | auto simp: cte_wp_at'_def dest!: imp)+

lemma maskedAsFull_null_cap[simp]:
  "(maskedAsFull x y = capability.NullCap) = (x = capability.NullCap)"
  "(capability.NullCap  = maskedAsFull x y) = (x = capability.NullCap)"
  by (case_tac x, auto simp:maskedAsFull_def isCap_simps )

lemma maskCapRights_eq_null:
  "(RetypeDecls_H.maskCapRights r xa = capability.NullCap) =
   (xa = capability.NullCap)"
  apply (cases xa; simp add: maskCapRights_def isCap_simps)
  apply (rename_tac arch_capability)
  apply (case_tac arch_capability)
      apply (simp_all add: ARM_H.maskCapRights_def isCap_simps)
  done

lemma cte_refs'_maskedAsFull[simp]:
  "cte_refs' (maskedAsFull a b) = cte_refs' a"
  apply (rule ext)+
  apply (case_tac a)
   apply (clarsimp simp:maskedAsFull_def isCap_simps)+
 done

crunches setExtraBadge, cteInsert
  for sc_at'_n[wp]: "sc_at'_n n p"
  (simp: crunch_simps wp: crunch_wps)

lemma tc_loop_corres:
  "\<lbrakk> list_all2 (\<lambda>(cap, slot) (cap', slot'). cap_relation cap cap'
             \<and> slot' = cte_map slot) caps caps';
      mi' = message_info_map mi \<rbrakk> \<Longrightarrow>
   corres ((=) \<circ> message_info_map)
      (\<lambda>s. valid_objs s \<and> pspace_aligned s \<and> pspace_distinct s \<and> valid_mdb s
         \<and> valid_list s
         \<and> (case ep of Some x \<Rightarrow> ep_at x s | _ \<Rightarrow> True)
         \<and> (\<forall>x \<in> set slots. cte_wp_at (\<lambda>cap. cap = cap.NullCap) x s \<and>
                             real_cte_at x s)
         \<and> (\<forall>(cap, slot) \<in> set caps. valid_cap cap s \<and>
                    cte_wp_at (\<lambda>cp'. (cap \<noteq> cap.NullCap \<longrightarrow> cp'\<noteq>cap \<longrightarrow> cp' = masked_as_full cap cap )) slot s )
         \<and> distinct slots
         \<and> in_user_frame buffer s)
      (\<lambda>s. valid_pspace' s
         \<and> (case ep of Some x \<Rightarrow> ep_at' x s | _ \<Rightarrow> True)
         \<and> (\<forall>x \<in> set (map cte_map slots).
             cte_wp_at' (\<lambda>cte. cteCap cte = NullCap) x s
                   \<and> real_cte_at' x s)
         \<and> distinct (map cte_map slots)
         \<and> valid_ipc_buffer_ptr' buffer s
         \<and> (\<forall>(cap, slot) \<in> set caps'. valid_cap' cap s \<and>
                    cte_wp_at' (\<lambda>cte. cap \<noteq> NullCap \<longrightarrow> cteCap cte \<noteq> cap \<longrightarrow> cteCap cte = maskedAsFull cap cap) slot s)
         \<and> 2 + msg_max_length + n + length caps' < unat max_ipc_words)
      (transfer_caps_loop ep buffer n caps slots mi)
      (transferCapsToSlots ep buffer n caps'
         (map cte_map slots) mi')"
  (is "\<lbrakk> list_all2 ?P caps caps'; ?v \<rbrakk> \<Longrightarrow> ?corres")
proof (induct caps caps' arbitrary: slots n mi mi' rule: list_all2_induct)
  case Nil
  show ?case using Nil.prems by (case_tac mi, simp)
next
  case (Cons x xs y ys slots n mi mi')
  note if_weak_cong[cong] if_cong [cong del]
  assume P: "?P x y"
  show ?case using Cons.prems P
    apply (clarsimp split del: if_split)
    apply (simp add: Let_def split_def word_size liftE_bindE
                     word_bits_conv[symmetric] split del: if_split)
    apply (rule corres_const_on_failure)
    apply (simp add: dc_def[symmetric] split del: if_split)
    apply (rule corres_guard_imp)
      apply (rule corres_if2)
        apply (case_tac "fst x", auto simp add: isCap_simps)[1]
       apply (rule corres_split [OF _ corres_set_extra_badge])
          apply (drule conjunct1)
          apply simp
          apply (rule corres_rel_imp, rule Cons.hyps, simp_all)[1]
          apply (case_tac mi, simp)
         apply (clarsimp simp: is_cap_simps)
        apply (simp add: split_def)
        apply (wp hoare_vcg_const_Ball_lift)
       apply (subgoal_tac "obj_ref_of (fst x) = capEPPtr (fst y)")
        prefer 2
        apply (clarsimp simp: is_cap_simps)
       apply (simp add: split_def)
       apply (wp hoare_vcg_const_Ball_lift)
      apply (rule_tac P="slots = []" and Q="slots \<noteq> []" in corres_disj_division)
        apply simp
       apply (rule corres_trivial, simp add: returnOk_def)
       apply (case_tac mi, simp)
      apply (simp add: list_case_If2 split del: if_split)
      apply (rule corres_splitEE)
         prefer 2
         apply (rule unifyFailure_discard2)
          apply (case_tac mi, clarsimp)
         apply (rule derive_cap_corres)
          apply (simp add: remove_rights_def)
         apply clarsimp
        apply (rule corres_split_norE)
           apply (simp add: liftE_bindE)
           apply (rule corres_split_nor)
              prefer 2
              apply (rule cins_corres, simp_all add: hd_map)[1]
             apply (simp add: tl_map)
             apply (rule corres_rel_imp, rule Cons.hyps, simp_all)[1]
            apply (wp valid_case_option_post_wp hoare_vcg_const_Ball_lift
                        hoare_vcg_const_Ball_lift cap_insert_weak_cte_wp_at)
             apply (wp hoare_vcg_const_Ball_lift | simp add:split_def del: imp_disj1)+
             apply (wp cap_insert_cte_wp_at)
           apply (wp valid_case_option_post_wp hoare_vcg_const_Ball_lift
                     cteInsert_valid_pspace
                     | simp add: split_def)+
           apply (wp cteInsert_weak_cte_wp_at hoare_valid_ipc_buffer_ptr_typ_at')+
           apply (wp hoare_vcg_const_Ball_lift cteInsert_cte_wp_at  valid_case_option_post_wp
             | simp add:split_def)+
          apply (rule corres_whenE)
            apply (case_tac cap', auto)[1]
           apply (rule corres_trivial, simp)
           apply (case_tac mi, simp)
          apply simp
         apply (unfold whenE_def)
         apply wp+
        apply (clarsimp simp: conj_comms ball_conj_distrib split del: if_split)
        apply (rule_tac Q' ="\<lambda>cap' s. (cap'\<noteq> cap.NullCap \<longrightarrow>
          cte_wp_at (is_derived (cdt s) (a, b) cap') (a, b) s
          \<and> QM s cap')" for QM
          in hoare_post_imp_R)
        prefer 2
         apply clarsimp
         apply assumption
        apply (subst imp_conjR)
        apply (rule hoare_vcg_conj_liftE_R)
        apply (rule derive_cap_is_derived)
       apply (wp derive_cap_is_derived_foo)+
      apply (simp split del: if_split)
      apply (rule_tac Q' ="\<lambda>cap' s. (cap'\<noteq> capability.NullCap \<longrightarrow>
         cte_wp_at' (\<lambda>c. is_derived' (ctes_of s) (cte_map (a, b)) cap' (cteCap c)) (cte_map (a, b)) s
         \<and> QM s cap')" for QM
        in hoare_post_imp_R)
      prefer 2
       apply clarsimp
       apply assumption
      apply (subst imp_conjR)
      apply (rule hoare_vcg_conj_liftE_R)
       apply (rule hoare_post_imp_R[OF deriveCap_derived])
       apply (clarsimp simp:cte_wp_at_ctes_of)
      apply (wp deriveCap_derived_foo)
     apply (clarsimp simp: cte_wp_at_caps_of_state remove_rights_def
                           real_cte_tcb_valid if_apply_def2
                split del: if_split)
     apply (rule conjI, (clarsimp split del: if_split)+)
     apply (clarsimp simp:conj_comms split del:if_split)
     apply (intro conjI allI)
       apply (clarsimp split:if_splits)
       apply (case_tac "cap = fst x",simp+)
      apply (clarsimp simp:masked_as_full_def is_cap_simps cap_master_cap_simps)
    apply (clarsimp split del: if_split)
    apply (intro conjI)
           apply (clarsimp simp:neq_Nil_conv)
        apply (drule hd_in_set)
        apply (drule(1) bspec)
        apply (clarsimp split:if_split_asm)
      apply (fastforce simp:neq_Nil_conv)
      apply (intro ballI conjI)
       apply (clarsimp simp:neq_Nil_conv)
      apply (intro impI)
      apply (drule(1) bspec[OF _ subsetD[rotated]])
       apply (clarsimp simp:neq_Nil_conv)
     apply (clarsimp split:if_splits)
    apply clarsimp
    apply (intro conjI)
     apply (drule(1) bspec,clarsimp)+
    subgoal for \<dots> aa _ _ capa
     by (case_tac "capa = aa"; clarsimp split:if_splits simp:masked_as_full_def is_cap_simps)
   apply (case_tac "isEndpointCap (fst y) \<and> capEPPtr (fst y) = the ep \<and> (\<exists>y. ep = Some y)")
    apply (clarsimp simp:conj_comms split del:if_split)
   apply (subst if_not_P)
    apply clarsimp
   apply (clarsimp simp:valid_pspace'_def cte_wp_at_ctes_of split del:if_split)
   apply (intro conjI)
    apply (case_tac  "cteCap cte = fst y",clarsimp simp: badge_derived'_def)
    apply (clarsimp simp: maskCapRights_eq_null maskedAsFull_def badge_derived'_def isCap_simps
                    split: if_split_asm)
  apply (clarsimp split del: if_split)
  apply (case_tac "fst y = capability.NullCap")
    apply (clarsimp simp: neq_Nil_conv split del: if_split)+
  apply (intro allI impI conjI)
     apply (clarsimp split:if_splits)
    apply (clarsimp simp:image_def)+
   apply (thin_tac "\<forall>x\<in>set ys. Q x" for Q)
   apply (drule(1) bspec)+
   apply clarsimp+
  apply (drule(1) bspec)
  apply (rule conjI)
   apply clarsimp+
  apply (case_tac "cteCap cteb = ab")
   by (clarsimp simp: isCap_simps maskedAsFull_def split:if_splits)+
qed

declare constOnFailure_wp [wp]

lemma transferCapsToSlots_pres1[crunch_rules]:
  assumes x: "\<And>cap src dest. \<lbrace>P\<rbrace> cteInsert cap src dest \<lbrace>\<lambda>rv. P\<rbrace>"
  assumes eb: "\<And>b n. \<lbrace>P\<rbrace> setExtraBadge buffer b n \<lbrace>\<lambda>_. P\<rbrace>"
  shows      "\<lbrace>P\<rbrace> transferCapsToSlots ep buffer n caps slots mi \<lbrace>\<lambda>rv. P\<rbrace>"
  apply (induct caps arbitrary: slots n mi)
   apply simp
  apply (simp add: Let_def split_def whenE_def
             cong: if_cong list.case_cong
             split del: if_split)
  apply (rule hoare_pre)
   apply (wp x eb | assumption | simp split del: if_split | wpc
             | wp (once) hoare_drop_imps)+
  done

lemma cteInsert_cte_cap_to':
  "\<lbrace>ex_cte_cap_to' p and cte_wp_at' (\<lambda>cte. cteCap cte = NullCap) dest\<rbrace>
   cteInsert cap src dest
   \<lbrace>\<lambda>rv. ex_cte_cap_to' p\<rbrace>"
  apply (simp add: ex_cte_cap_to'_def)
  apply (rule hoare_pre)
   apply (rule hoare_use_eq_irq_node' [OF cteInsert_ksInterruptState])
   apply (clarsimp simp:cteInsert_def)
    apply (wp hoare_vcg_ex_lift  updateMDB_weak_cte_wp_at updateCap_cte_wp_at_cases
      setUntypedCapAsFull_cte_wp_at getCTE_wp static_imp_wp)
   apply (clarsimp simp:cte_wp_at_ctes_of)
   apply (rule_tac x = "cref" in exI)
     apply (rule conjI)
     apply clarsimp+
  done

declare maskCapRights_eq_null[simp]

crunch ex_cte_cap_wp_to' [wp]: setExtraBadge "ex_cte_cap_wp_to' P p"
  (rule: ex_cte_cap_to'_pres)

crunch valid_objs' [wp]: setExtraBadge valid_objs'
crunch aligned' [wp]: setExtraBadge pspace_aligned'
crunch distinct' [wp]: setExtraBadge pspace_distinct'

lemma cteInsert_assume_Null:
  "\<lbrace>P\<rbrace> cteInsert cap src dest \<lbrace>Q\<rbrace> \<Longrightarrow>
   \<lbrace>\<lambda>s. cte_wp_at' (\<lambda>cte. cteCap cte = NullCap) dest s \<longrightarrow> P s\<rbrace>
   cteInsert cap src dest
   \<lbrace>Q\<rbrace>"
  apply (rule hoare_name_pre_state)
  apply (erule impCE)
   apply (simp add: cteInsert_def)
   apply (rule hoare_seq_ext[OF _ getCTE_sp])+
   apply (rule hoare_name_pre_state)
   apply (clarsimp simp: cte_wp_at_ctes_of)
  apply (erule hoare_pre(1))
  apply simp
  done

crunch mdb'[wp]: setExtraBadge valid_mdb'

lemma cteInsert_weak_cte_wp_at2:
  assumes weak:"\<And>c cap. P (maskedAsFull c cap) = P c"
  shows
    "\<lbrace>\<lambda>s. if p = dest then P cap else cte_wp_at' (\<lambda>c. P (cteCap c)) p s\<rbrace>
     cteInsert cap src dest
     \<lbrace>\<lambda>uu. cte_wp_at' (\<lambda>c. P (cteCap c)) p\<rbrace>"
  apply (rule hoare_pre)
   apply (rule hoare_use_eq_irq_node' [OF cteInsert_ksInterruptState])
   apply (clarsimp simp:cteInsert_def)
    apply (wp hoare_vcg_ex_lift  updateMDB_weak_cte_wp_at updateCap_cte_wp_at_cases
      setUntypedCapAsFull_cte_wp_at getCTE_wp static_imp_wp)
   apply (clarsimp simp:cte_wp_at_ctes_of weak)
   apply auto
  done

lemma transferCapsToSlots_presM:
  assumes x: "\<And>cap src dest. \<lbrace>\<lambda>s. P s \<and> (emx \<longrightarrow> cte_wp_at' (\<lambda>cte. cteCap cte = NullCap) dest s \<and> ex_cte_cap_to' dest s)
                                       \<and> (vo \<longrightarrow> valid_objs' s \<and> valid_cap' cap s \<and> real_cte_at' dest s)
                                       \<and> (drv \<longrightarrow> cte_wp_at' (is_derived' (ctes_of s) src cap \<circ> cteCap) src s
                                               \<and> cte_wp_at' (untyped_derived_eq cap o cteCap) src s
                                               \<and> valid_mdb' s)
                                       \<and> (pad \<longrightarrow> pspace_aligned' s \<and> pspace_distinct' s)\<rbrace>
                                           cteInsert cap src dest \<lbrace>\<lambda>rv. P\<rbrace>"
  assumes eb: "\<And>b n. \<lbrace>P\<rbrace> setExtraBadge buffer b n \<lbrace>\<lambda>_. P\<rbrace>"
  shows      "\<lbrace>\<lambda>s. P s
                 \<and> (emx \<longrightarrow> (\<forall>x \<in> set slots. ex_cte_cap_to' x s \<and> cte_wp_at' (\<lambda>cte. cteCap cte = NullCap) x s) \<and> distinct slots)
                 \<and> (vo \<longrightarrow> valid_objs' s \<and> (\<forall>x \<in> set slots. real_cte_at' x s \<and> cte_wp_at' (\<lambda>cte. cteCap cte = NullCap) x s)
                           \<and> (\<forall>x \<in> set caps. s \<turnstile>' fst x ) \<and> distinct slots)
                 \<and> (pad \<longrightarrow> pspace_aligned' s \<and> pspace_distinct' s)
                 \<and> (drv \<longrightarrow> vo \<and> pspace_aligned' s \<and> pspace_distinct' s \<and> valid_mdb' s
                         \<and> length slots \<le> 1
                         \<and> (\<forall>x \<in> set caps. s \<turnstile>' fst x \<and> (slots \<noteq> []
                              \<longrightarrow> cte_wp_at' (\<lambda>cte. fst x \<noteq> NullCap \<longrightarrow> cteCap cte = fst x) (snd x) s)))\<rbrace>
                 transferCapsToSlots ep buffer n caps slots mi
              \<lbrace>\<lambda>rv. P\<rbrace>"
  apply (induct caps arbitrary: slots n mi)
   apply (simp, wp, simp)
  apply (simp add: Let_def split_def whenE_def
             cong: if_cong list.case_cong split del: if_split)
  apply (rule hoare_pre)
   apply (wp eb hoare_vcg_const_Ball_lift hoare_vcg_const_imp_lift
           | assumption | wpc)+
     apply (rule cteInsert_assume_Null)
     apply (wp x hoare_vcg_const_Ball_lift cteInsert_cte_cap_to' static_imp_wp)
       apply (rule cteInsert_weak_cte_wp_at2,clarsimp)
      apply (wp hoare_vcg_const_Ball_lift static_imp_wp)+
       apply (rule cteInsert_weak_cte_wp_at2,clarsimp)
      apply (wp hoare_vcg_const_Ball_lift cteInsert_cte_wp_at static_imp_wp
          deriveCap_derived_foo)+
  apply (thin_tac "\<And>slots. PROP P slots" for P)
  apply (clarsimp simp: cte_wp_at_ctes_of remove_rights_def
                        real_cte_tcb_valid if_apply_def2
             split del: if_split)
  apply (rule conjI)
   apply (clarsimp simp:cte_wp_at_ctes_of untyped_derived_eq_def)
  apply (intro conjI allI)
     apply (clarsimp simp:Fun.comp_def cte_wp_at_ctes_of)+
  apply (clarsimp simp:valid_capAligned)
  done

lemmas transferCapsToSlots_pres2
    = transferCapsToSlots_presM[where vo=False and emx=True
                                  and drv=False and pad=False, simplified]

lemma transferCapsToSlots_aligned'[wp]:
  "\<lbrace>pspace_aligned'\<rbrace>
     transferCapsToSlots ep buffer n caps slots mi
   \<lbrace>\<lambda>rv. pspace_aligned'\<rbrace>"
  by (wp transferCapsToSlots_pres1)

lemma transferCapsToSlots_distinct'[wp]:
  "\<lbrace>pspace_distinct'\<rbrace>
     transferCapsToSlots ep buffer n caps slots mi
   \<lbrace>\<lambda>rv. pspace_distinct'\<rbrace>"
  by (wp transferCapsToSlots_pres1)

lemma transferCapsToSlots_typ_at'[wp]:
   "\<lbrace>\<lambda>s. P (typ_at' T p s)\<rbrace>
      transferCapsToSlots ep buffer n caps slots mi
    \<lbrace>\<lambda>rv s. P (typ_at' T p s)\<rbrace>"
  by (wp transferCapsToSlots_pres1 setExtraBadge_typ_at')

lemma transferCapsToSlots_valid_objs[wp]:
  "\<lbrace>valid_objs' and valid_mdb' and (\<lambda>s. \<forall>x \<in> set slots. real_cte_at' x s \<and> cte_wp_at' (\<lambda>cte. cteCap cte = capability.NullCap) x s)
       and (\<lambda>s. \<forall>x \<in> set caps. s \<turnstile>' fst x) and K(distinct slots)\<rbrace>
       transferCapsToSlots ep buffer n caps slots mi
   \<lbrace>\<lambda>rv. valid_objs'\<rbrace>"
  apply (rule hoare_pre)
   apply (rule transferCapsToSlots_presM[where vo=True and emx=False and drv=False and pad=False])
    apply (wp | simp)+
  done

abbreviation(input)
  "transferCaps_srcs caps s \<equiv> \<forall>x\<in>set caps. cte_wp_at' (\<lambda>cte. fst x \<noteq> NullCap \<longrightarrow> cteCap cte = fst x) (snd x) s"

lemma transferCapsToSlots_mdb[wp]:
  "\<lbrace>\<lambda>s. valid_pspace' s \<and> distinct slots
          \<and> length slots \<le> 1
          \<and> (\<forall>x \<in> set slots. ex_cte_cap_to' x s \<and> cte_wp_at' (\<lambda>cte. cteCap cte = capability.NullCap) x s)
          \<and> (\<forall>x \<in> set slots. real_cte_at' x s)
          \<and> transferCaps_srcs caps s\<rbrace>
    transferCapsToSlots ep buffer n caps slots mi
   \<lbrace>\<lambda>rv. valid_mdb'\<rbrace>"
  apply (wp transferCapsToSlots_presM[where drv=True and vo=True and emx=True and pad=True])
    apply clarsimp
    apply (frule valid_capAligned)
    apply (clarsimp simp: cte_wp_at_ctes_of is_derived'_def badge_derived'_def)
   apply wp
  apply (clarsimp simp: valid_pspace'_def)
  apply (clarsimp simp:cte_wp_at_ctes_of)
  apply (drule(1) bspec,clarify)
  apply (case_tac cte)
  apply (clarsimp dest!:ctes_of_valid_cap' split:if_splits)
  apply (fastforce simp:valid_cap'_def)
  done

crunch no_0' [wp]: setExtraBadge no_0_obj'

lemma transferCapsToSlots_no_0_obj' [wp]:
  "\<lbrace>no_0_obj'\<rbrace> transferCapsToSlots ep buffer n caps slots mi \<lbrace>\<lambda>rv. no_0_obj'\<rbrace>"
  by (wp transferCapsToSlots_pres1)

lemma transferCapsToSlots_vp[wp]:
  "\<lbrace>\<lambda>s. valid_pspace' s \<and> distinct slots
          \<and> length slots \<le> 1
          \<and> (\<forall>x \<in> set slots. ex_cte_cap_to' x s \<and> cte_wp_at' (\<lambda>cte. cteCap cte = capability.NullCap) x s)
          \<and> (\<forall>x \<in> set slots. real_cte_at' x s)
          \<and> transferCaps_srcs caps s\<rbrace>
    transferCapsToSlots ep buffer n caps slots mi
   \<lbrace>\<lambda>rv. valid_pspace'\<rbrace>"
  apply (rule hoare_pre)
   apply (simp add: valid_pspace'_def | wp)+
  apply (fastforce simp: cte_wp_at_ctes_of dest: ctes_of_valid')
  done

crunches setExtraBadge, doIPCTransfer
  for sch_act [wp]: "\<lambda>s. P (ksSchedulerAction s)"
  (wp: crunch_wps mapME_wp' simp: zipWithM_x_mapM)
crunches setExtraBadge
  for pred_tcb_at' [wp]: "\<lambda>s. pred_tcb_at' proj P p s"
  and ksCurThread[wp]: "\<lambda>s. P (ksCurThread s)"
  and ksCurDomain[wp]: "\<lambda>s. P (ksCurDomain s)"
  and obj_at' [wp]: "\<lambda>s. P' (obj_at' P p s)"
  and queues [wp]: "\<lambda>s. P (ksReadyQueues s)"
  and queuesL1 [wp]: "\<lambda>s. P (ksReadyQueuesL1Bitmap s)"
  and queuesL2 [wp]: "\<lambda>s. P (ksReadyQueuesL2Bitmap s)"

lemma tcts_sch_act[wp]:
  "\<lbrace>\<lambda>s. sch_act_wf (ksSchedulerAction s) s\<rbrace>
     transferCapsToSlots ep buffer n caps slots mi
   \<lbrace>\<lambda>rv s. sch_act_wf (ksSchedulerAction s) s\<rbrace>"
  by (wp sch_act_wf_lift tcb_in_cur_domain'_lift transferCapsToSlots_pres1)

lemma tcts_vq[wp]:
  "\<lbrace>Invariants_H.valid_queues\<rbrace> transferCapsToSlots ep buffer n caps slots mi \<lbrace>\<lambda>rv. Invariants_H.valid_queues\<rbrace>"
  by (wp valid_queues_lift transferCapsToSlots_pres1)

lemma tcts_vq'[wp]:
  "\<lbrace>valid_queues'\<rbrace> transferCapsToSlots ep buffer n caps slots mi \<lbrace>\<lambda>rv. valid_queues'\<rbrace>"
  by (wp valid_queues_lift' transferCapsToSlots_pres1)

crunch state_refs_of' [wp]: setExtraBadge "\<lambda>s. P (state_refs_of' s)"

lemma tcts_state_refs_of'[wp]:
  "\<lbrace>\<lambda>s. P (state_refs_of' s)\<rbrace>
     transferCapsToSlots ep buffer n caps slots mi
   \<lbrace>\<lambda>rv s. P (state_refs_of' s)\<rbrace>"
  by (wp transferCapsToSlots_pres1)

crunch if_live' [wp]: setExtraBadge if_live_then_nonz_cap'

lemma tcts_iflive[wp]:
  "\<lbrace>\<lambda>s. if_live_then_nonz_cap' s \<and> distinct slots \<and>
         (\<forall>x\<in>set slots.
             ex_cte_cap_to' x s \<and> cte_wp_at' (\<lambda>cte. cteCap cte = capability.NullCap) x s)\<rbrace>
  transferCapsToSlots ep buffer n caps slots mi
   \<lbrace>\<lambda>rv. if_live_then_nonz_cap'\<rbrace>"
  by (wp transferCapsToSlots_pres2 | simp)+

crunches setExtraBadge
  for valid_idle'[wp]: valid_idle'
  and if_unsafe'[wp]: if_unsafe_then_cap'

lemma tcts_ifunsafe[wp]:
  "\<lbrace>\<lambda>s. if_unsafe_then_cap' s \<and> distinct slots \<and>
         (\<forall>x\<in>set slots.  cte_wp_at' (\<lambda>cte. cteCap cte = capability.NullCap) x s \<and>
             ex_cte_cap_to' x s)\<rbrace> transferCapsToSlots ep buffer n caps slots mi
   \<lbrace>\<lambda>rv. if_unsafe_then_cap'\<rbrace>"
  by (wp transferCapsToSlots_pres2 | simp)+

lemma tcts_idle'[wp]:
  "\<lbrace>\<lambda>s. valid_idle' s\<rbrace> transferCapsToSlots ep buffer n caps slots mi
   \<lbrace>\<lambda>rv. valid_idle'\<rbrace>"
  apply (rule hoare_pre)
   apply (wp transferCapsToSlots_pres1)
  apply simp
  done

lemma tcts_ct[wp]:
  "\<lbrace>cur_tcb'\<rbrace> transferCapsToSlots ep buffer n caps slots mi \<lbrace>\<lambda>rv. cur_tcb'\<rbrace>"
  by (wp transferCapsToSlots_pres1 cur_tcb_lift)

crunch valid_arch_state' [wp]: setExtraBadge valid_arch_state'

lemma transferCapsToSlots_valid_arch [wp]:
  "\<lbrace>valid_arch_state'\<rbrace> transferCapsToSlots ep buffer n caps slots mi \<lbrace>\<lambda>rv. valid_arch_state'\<rbrace>"
  by (rule transferCapsToSlots_pres1; wp)

crunch valid_global_refs' [wp]: setExtraBadge valid_global_refs'

lemma transferCapsToSlots_valid_globals [wp]:
  "\<lbrace>valid_global_refs' and valid_objs' and valid_mdb' and pspace_distinct' and pspace_aligned' and K (distinct slots)
         and K (length slots \<le> 1)
         and (\<lambda>s. \<forall>x \<in> set slots. real_cte_at' x s \<and> cte_wp_at' (\<lambda>cte. cteCap cte = capability.NullCap) x s)
  and transferCaps_srcs caps\<rbrace>
  transferCapsToSlots ep buffer n caps slots mi
  \<lbrace>\<lambda>rv. valid_global_refs'\<rbrace>"
  apply (wp transferCapsToSlots_presM[where vo=True and emx=False and drv=True and pad=True] | clarsimp)+
  apply (clarsimp simp:cte_wp_at_ctes_of)
  apply (drule(1) bspec,clarsimp)
  apply (case_tac cte,clarsimp)
  apply (frule(1) CSpace_I.ctes_of_valid_cap')
  apply (fastforce simp:valid_cap'_def)
  done

crunch irq_node' [wp]: setExtraBadge "\<lambda>s. P (irq_node' s)"

lemma transferCapsToSlots_irq_node'[wp]:
  "\<lbrace>\<lambda>s. P (irq_node' s)\<rbrace> transferCapsToSlots ep buffer n caps slots mi \<lbrace>\<lambda>rv s. P (irq_node' s)\<rbrace>"
   by (wp transferCapsToSlots_pres1)

lemma valid_irq_handlers_ctes_ofD:
  "\<lbrakk> ctes_of s p = Some cte; cteCap cte = IRQHandlerCap irq; valid_irq_handlers' s \<rbrakk>
       \<Longrightarrow> irq_issued' irq s"
  by (auto simp: valid_irq_handlers'_def cteCaps_of_def ran_def)

crunch valid_irq_handlers' [wp]: setExtraBadge valid_irq_handlers'

lemma transferCapsToSlots_irq_handlers[wp]:
  "\<lbrace>valid_irq_handlers' and valid_objs' and valid_mdb' and pspace_distinct' and pspace_aligned'
         and K(distinct slots \<and> length slots \<le> 1)
         and (\<lambda>s. \<forall>x \<in> set slots. real_cte_at' x s \<and> cte_wp_at' (\<lambda>cte. cteCap cte = capability.NullCap) x s)
         and transferCaps_srcs caps\<rbrace>
     transferCapsToSlots ep buffer n caps slots mi
  \<lbrace>\<lambda>rv. valid_irq_handlers'\<rbrace>"
  apply (wp transferCapsToSlots_presM[where vo=True and emx=False and drv=True and pad=False])
     apply (clarsimp simp: is_derived'_def cte_wp_at_ctes_of badge_derived'_def)
     apply (erule(2) valid_irq_handlers_ctes_ofD)
    apply wp
  apply (clarsimp simp:cte_wp_at_ctes_of | intro ballI conjI)+
  apply (drule(1) bspec,clarsimp)
  apply (case_tac cte,clarsimp)
  apply (frule(1) CSpace_I.ctes_of_valid_cap')
  apply (fastforce simp:valid_cap'_def)
  done

crunch irq_state' [wp]: setExtraBadge "\<lambda>s. P (ksInterruptState s)"

lemma setExtraBadge_irq_states'[wp]:
  "\<lbrace>valid_irq_states'\<rbrace> setExtraBadge buffer b n \<lbrace>\<lambda>_. valid_irq_states'\<rbrace>"
  apply (wp valid_irq_states_lift')
   apply (simp add: setExtraBadge_def storeWordUser_def)
   apply (wpsimp wp: no_irq dmo_lift' no_irq_storeWord)
  apply assumption
  done

lemma transferCapsToSlots_irq_states' [wp]:
  "\<lbrace>valid_irq_states'\<rbrace> transferCapsToSlots ep buffer n caps slots mi \<lbrace>\<lambda>_. valid_irq_states'\<rbrace>"
  by (wp transferCapsToSlots_pres1)

crunch valid_pde_mappings' [wp]: setExtraBadge valid_pde_mappings'

lemma transferCapsToSlots_pde_mappings'[wp]:
  "\<lbrace>valid_pde_mappings'\<rbrace> transferCapsToSlots ep buffer n caps slots mi \<lbrace>\<lambda>rv. valid_pde_mappings'\<rbrace>"
  by (wp transferCapsToSlots_pres1)

lemma transferCapsToSlots_irqs_masked'[wp]:
  "\<lbrace>irqs_masked'\<rbrace> transferCapsToSlots ep buffer n caps slots mi \<lbrace>\<lambda>rv. irqs_masked'\<rbrace>"
  by (wp transferCapsToSlots_pres1 irqs_masked_lift)

lemma storeWordUser_vms'[wp]:
  "\<lbrace>valid_machine_state'\<rbrace> storeWordUser a w \<lbrace>\<lambda>_. valid_machine_state'\<rbrace>"
proof -
  have aligned_offset_ignore:
    "\<And>(l::word32) (p::word32) sz. l<4 \<Longrightarrow> p && mask 2 = 0 \<Longrightarrow>
       p+l && ~~ mask pageBits = p && ~~ mask pageBits"
  proof -
    fix l p sz
    assume al: "(p::word32) && mask 2 = 0"
    assume "(l::word32) < 4" hence less: "l<2^2" by simp
    have le: "2 \<le> pageBits" by (simp add: pageBits_def)
    show "?thesis l p sz"
      by (rule is_aligned_add_helper[simplified is_aligned_mask,
          THEN conjunct2, THEN mask_out_first_mask_some,
          where n=2, OF al less le])
  qed

  show ?thesis
    apply (simp add: valid_machine_state'_def storeWordUser_def
                     doMachineOp_def split_def)
    apply wp
    apply clarsimp
    apply (drule use_valid)
    apply (rule_tac x=p in storeWord_um_inv, simp+)
    apply (drule_tac x=p in spec)
    apply (erule disjE, simp_all)
    apply (erule conjE)
    apply (erule disjE, simp)
    apply (simp add: pointerInUserData_def word_size)
    apply (subgoal_tac "a && ~~ mask pageBits = p && ~~ mask pageBits", simp)
    apply (simp only: is_aligned_mask[of _ 2])
    apply (elim disjE, simp_all)
      apply (rule aligned_offset_ignore[symmetric], simp+)+
    done
qed

lemma setExtraBadge_vms'[wp]:
  "\<lbrace>valid_machine_state'\<rbrace> setExtraBadge buffer b n \<lbrace>\<lambda>_. valid_machine_state'\<rbrace>"
by (simp add: setExtraBadge_def) wp

lemma transferCapsToSlots_vms[wp]:
  "\<lbrace>\<lambda>s. valid_machine_state' s\<rbrace>
   transferCapsToSlots ep buffer n caps slots mi
   \<lbrace>\<lambda>_ s. valid_machine_state' s\<rbrace>"
  by (wp transferCapsToSlots_pres1)

crunches setExtraBadge, transferCapsToSlots
  for pspace_domain_valid[wp]: "pspace_domain_valid"

crunch ct_not_inQ[wp]: setExtraBadge "ct_not_inQ"

lemma tcts_ct_not_inQ[wp]:
  "\<lbrace>ct_not_inQ\<rbrace>
   transferCapsToSlots ep buffer n caps slots mi
   \<lbrace>\<lambda>_. ct_not_inQ\<rbrace>"
  by (wp transferCapsToSlots_pres1)

crunch gsUntypedZeroRanges[wp]: setExtraBadge "\<lambda>s. P (gsUntypedZeroRanges s)"
crunch ctes_of[wp]: setExtraBadge "\<lambda>s. P (ctes_of s)"

lemma tcts_zero_ranges[wp]:
  "\<lbrace>\<lambda>s. untyped_ranges_zero' s \<and> valid_pspace' s \<and> distinct slots
          \<and> (\<forall>x \<in> set slots. ex_cte_cap_to' x s \<and> cte_wp_at' (\<lambda>cte. cteCap cte = capability.NullCap) x s)
          \<and> (\<forall>x \<in> set slots. real_cte_at' x s)
          \<and> length slots \<le> 1
          \<and> transferCaps_srcs caps s\<rbrace>
    transferCapsToSlots ep buffer n caps slots mi
  \<lbrace>\<lambda>rv. untyped_ranges_zero'\<rbrace>"
  apply (wp transferCapsToSlots_presM[where emx=True and vo=True
      and drv=True and pad=True])
    apply (clarsimp simp: cte_wp_at_ctes_of)
   apply (simp add: cteCaps_of_def)
   apply (rule hoare_pre, wp untyped_ranges_zero_lift)
   apply (simp add: o_def)
  apply (clarsimp simp: valid_pspace'_def ball_conj_distrib[symmetric])
  apply (drule(1) bspec)
  apply (clarsimp simp: cte_wp_at_ctes_of)
  apply (case_tac cte, clarsimp)
  apply (frule(1) ctes_of_valid_cap')
  apply auto[1]
  done

crunches setExtraBadge, transferCapsToSlots
  for ct_idle_or_in_cur_domain'[wp]: ct_idle_or_in_cur_domain'
  and ksDomSchedule[wp]: "\<lambda>s. P (ksDomSchedule s)"
  and ksDomScheduleIdx[wp]: "\<lambda>s. P (ksDomScheduleIdx s)"
  and ksCurDomain[wp]: "\<lambda>s. P (ksCurDomain s)"
  and replies_of'[wp]: "\<lambda>s. P (replies_of' s)"

lemma transferCapsToSlots_invs[wp]:
  "\<lbrace>\<lambda>s. invs' s \<and> distinct slots
          \<and> (\<forall>x \<in> set slots. cte_wp_at' (\<lambda>cte. cteCap cte = NullCap) x s)
          \<and> (\<forall>x \<in> set slots. ex_cte_cap_to' x s)
          \<and> (\<forall>x \<in> set slots. real_cte_at' x s)
          \<and> length slots \<le> 1
          \<and> transferCaps_srcs caps s\<rbrace>
    transferCapsToSlots ep buffer n caps slots mi
   \<lbrace>\<lambda>rv. invs'\<rbrace>"
  apply (simp add: invs'_def valid_state'_def)
  apply (wp valid_irq_node_lift)
  sorry (* valid_release_queue
  apply fastforce
  done *)

lemma grs_distinct'[wp]:
  "\<lbrace>\<top>\<rbrace> getReceiveSlots t buf \<lbrace>\<lambda>rv s. distinct rv\<rbrace>"
  apply (cases buf, simp_all add: getReceiveSlots_def
                                  split_def unlessE_def)
   apply (wp, simp)
  apply (wp | simp only: distinct.simps list.simps empty_iff)+
  apply simp
  done

lemma tc_corres:
  "\<lbrakk> info' = message_info_map info;
    list_all2 (\<lambda>x y. cap_relation (fst x) (fst y) \<and> snd y = cte_map (snd x))
         caps caps' \<rbrakk>
  \<Longrightarrow>
   corres ((=) \<circ> message_info_map)
   (tcb_at receiver and valid_objs and
    pspace_aligned and pspace_distinct and valid_mdb
    and valid_list
    and (\<lambda>s. case ep of Some x \<Rightarrow> ep_at x s | _ \<Rightarrow> True)
    and case_option \<top> in_user_frame recv_buf
    and (\<lambda>s. valid_message_info info)
    and transfer_caps_srcs caps)
   (tcb_at' receiver and valid_objs' and
    pspace_aligned' and pspace_distinct' and no_0_obj' and valid_mdb'
    and (\<lambda>s. case ep of Some x \<Rightarrow> ep_at' x s | _ \<Rightarrow> True)
    and case_option \<top> valid_ipc_buffer_ptr' recv_buf
    and transferCaps_srcs caps'
    and (\<lambda>s. length caps' \<le> msgMaxExtraCaps))
   (transfer_caps info caps ep receiver recv_buf)
   (transferCaps info' caps' ep receiver recv_buf)"
  apply (simp add: transfer_caps_def transferCaps_def
                   getThreadCSpaceRoot)
  apply (rule corres_assume_pre)
  apply (rule corres_guard_imp)
    apply (rule corres_split [OF _ get_recv_slot_corres])
      apply (rule_tac x=recv_buf in option_corres)
       apply (rule_tac P=\<top> and P'=\<top> in corres_inst)
       apply (case_tac info, simp)
      apply simp
      apply (rule corres_rel_imp, rule tc_loop_corres,
             simp_all add: split_def)[1]
      apply (case_tac info, simp)
     apply (wp hoare_vcg_all_lift get_rs_cte_at static_imp_wp
                | simp only: ball_conj_distrib)+
   apply (simp add: cte_map_def tcb_cnode_index_def split_def)
   apply (clarsimp simp: valid_pspace'_def valid_ipc_buffer_ptr'_def2
                        split_def
                  cong: option.case_cong)
   apply (drule(1) bspec)
   apply (clarsimp simp:cte_wp_at_caps_of_state)
   apply (frule(1) Invariants_AI.caps_of_state_valid)
   apply (fastforce simp:valid_cap_def)
  apply (cases info)
  apply (clarsimp simp: msg_max_extra_caps_def valid_message_info_def
                        max_ipc_words msg_max_length_def
                        msgMaxExtraCaps_def msgExtraCapBits_def
                        shiftL_nat valid_pspace'_def)
  apply (drule(1) bspec)
  apply (clarsimp simp:cte_wp_at_ctes_of)
  apply (case_tac cte,clarsimp)
  apply (frule(1) ctes_of_valid_cap')
  apply (fastforce simp:valid_cap'_def)
  done

crunch typ_at'[wp]: transferCaps "\<lambda>s. P (typ_at' T p s)"

lemmas transferCaps_typ_ats[wp] = typ_at_lifts [OF transferCaps_typ_at']

declare maskCapRights_Reply [simp]

lemma isIRQControlCap_mask [simp]:
  "isIRQControlCap (maskCapRights R c) = isIRQControlCap c"
  apply (case_tac c)
            apply (clarsimp simp: isCap_simps maskCapRights_def Let_def)+
      apply (rename_tac arch_capability)
      apply (case_tac arch_capability)
          apply (clarsimp simp: isCap_simps ARM_H.maskCapRights_def
                                maskCapRights_def Let_def)+
  done

lemma isPageCap_maskCapRights[simp]:
  "isArchCap isPageCap (RetypeDecls_H.maskCapRights R c) = isArchCap isPageCap c"
  apply (case_tac c; simp add: isCap_simps isArchCap_def maskCapRights_def)
  apply (rename_tac arch_capability)
  apply (case_tac arch_capability; simp add: isCap_simps ARM_H.maskCapRights_def)
  done

lemma is_derived_mask' [simp]:
  "is_derived' m p (maskCapRights R c) = is_derived' m p c"
  apply (rule ext)
  apply (simp add: is_derived'_def badge_derived'_def)
  done

lemma updateCapData_ordering:
  "\<lbrakk> (x, capBadge cap) \<in> capBadge_ordering P; updateCapData p d cap \<noteq> NullCap \<rbrakk>
    \<Longrightarrow> (x, capBadge (updateCapData p d cap)) \<in> capBadge_ordering P"
  apply (cases cap, simp_all add: updateCapData_def isCap_simps Let_def
                                  capBadge_def ARM_H.updateCapData_def
                           split: if_split_asm)
   apply fastforce+
  done

lemma lookup_cap_to'[wp]:
  "\<lbrace>\<top>\<rbrace> lookupCap t cref \<lbrace>\<lambda>rv s. \<forall>r\<in>cte_refs' rv (irq_node' s). ex_cte_cap_to' r s\<rbrace>,-"
  by (simp add: lookupCap_def lookupCapAndSlot_def | wp)+

lemma grs_cap_to'[wp]:
  "\<lbrace>\<top>\<rbrace> getReceiveSlots t buf \<lbrace>\<lambda>rv s. \<forall>x \<in> set rv. ex_cte_cap_to' x s\<rbrace>"
  apply (cases buf; simp add: getReceiveSlots_def split_def unlessE_def)
   apply (wp, simp)
  apply (wp | simp | rule hoare_drop_imps)+
  done

lemma grs_length'[wp]:
  "\<lbrace>\<lambda>s. 1 \<le> n\<rbrace> getReceiveSlots receiver recv_buf \<lbrace>\<lambda>rv s. length rv \<le> n\<rbrace>"
  apply (simp add: getReceiveSlots_def split_def unlessE_def)
  apply (rule hoare_pre)
   apply (wp | wpc | simp)+
  done

lemma transferCaps_invs' [wp]:
  "\<lbrace>invs' and transferCaps_srcs caps\<rbrace>
    transferCaps mi caps ep receiver recv_buf
   \<lbrace>\<lambda>rv. invs'\<rbrace>"
  apply (simp add: transferCaps_def Let_def split_def)
  apply (wp get_rs_cte_at' hoare_vcg_const_Ball_lift
             | wpcw | clarsimp)+
  done

lemma get_mrs_inv'[wp]:
  "\<lbrace>P\<rbrace> getMRs t buf info \<lbrace>\<lambda>rv. P\<rbrace>"
  by (simp add: getMRs_def load_word_offs_def getRegister_def
          | wp dmo_inv' loadWord_inv mapM_wp'
            asUser_inv det_mapM[where S=UNIV] | wpc)+


lemma copyMRs_typ_at':
  "\<lbrace>\<lambda>s. P (typ_at' T p s)\<rbrace> copyMRs s sb r rb n \<lbrace>\<lambda>rv s. P (typ_at' T p s)\<rbrace>"
  by (simp add: copyMRs_def | wp mapM_wp [where S=UNIV, simplified] | wpc)+

lemmas copyMRs_typ_at_lifts[wp] = typ_at_lifts [OF copyMRs_typ_at']

lemma copy_mrs_invs'[wp]:
  "\<lbrace> invs' and tcb_at' s and tcb_at' r \<rbrace> copyMRs s sb r rb n \<lbrace>\<lambda>rv. invs' \<rbrace>"
  including no_pre
  apply (simp add: copyMRs_def)
  apply (wp dmo_invs' no_irq_mapM no_irq_storeWord|
         simp add: split_def)
   apply (case_tac sb, simp_all)[1]
    apply wp+
   apply (case_tac rb, simp_all)[1]
   apply (wp mapM_wp dmo_invs' no_irq_mapM no_irq_storeWord no_irq_loadWord)
   apply blast
  apply (rule hoare_strengthen_post)
   apply (rule mapM_wp)
    apply (wp | simp | blast)+
  done

crunch aligned'[wp]: transferCaps pspace_aligned'
  (wp: crunch_wps simp: zipWithM_x_mapM)
crunch distinct'[wp]: transferCaps pspace_distinct'
  (wp: crunch_wps simp: zipWithM_x_mapM)

crunch aligned'[wp]: copyMRs pspace_aligned'
  (wp: crunch_wps simp: crunch_simps wp: crunch_wps)
crunch distinct'[wp]: copyMRs pspace_distinct'
  (wp: crunch_wps simp: crunch_simps wp: crunch_wps)

lemma set_mrs_valid_objs' [wp]:
  "\<lbrace>valid_objs'\<rbrace> setMRs t a msgs \<lbrace>\<lambda>rv. valid_objs'\<rbrace>"
  apply (simp add: setMRs_def zipWithM_x_mapM split_def)
  apply (wp asUser_valid_objs crunch_wps)
  done

crunch valid_objs'[wp]: copyMRs valid_objs'
  (wp: crunch_wps simp: crunch_simps)


lemma setMRs_invs_bits[wp]:
  "\<lbrace>valid_pspace'\<rbrace> setMRs t buf mrs \<lbrace>\<lambda>rv. valid_pspace'\<rbrace>"
  "\<lbrace>\<lambda>s. sch_act_wf (ksSchedulerAction s) s\<rbrace>
     setMRs t buf mrs \<lbrace>\<lambda>rv s. sch_act_wf (ksSchedulerAction s) s\<rbrace>"
  "\<lbrace>\<lambda>s. weak_sch_act_wf (ksSchedulerAction s) s\<rbrace>
     setMRs t buf mrs \<lbrace>\<lambda>rv s. weak_sch_act_wf (ksSchedulerAction s) s\<rbrace>"
  "\<lbrace>Invariants_H.valid_queues\<rbrace> setMRs t buf mrs \<lbrace>\<lambda>rv. Invariants_H.valid_queues\<rbrace>"
  "\<lbrace>valid_queues'\<rbrace> setMRs t buf mrs \<lbrace>\<lambda>rv. valid_queues'\<rbrace>"
  "\<lbrace>\<lambda>s. P (state_refs_of' s)\<rbrace>
     setMRs t buf mrs
   \<lbrace>\<lambda>rv s. P (state_refs_of' s)\<rbrace>"
  "\<lbrace>if_live_then_nonz_cap'\<rbrace> setMRs t buf mrs \<lbrace>\<lambda>rv. if_live_then_nonz_cap'\<rbrace>"
  "\<lbrace>ex_nonz_cap_to' p\<rbrace> setMRs t buf mrs \<lbrace>\<lambda>rv. ex_nonz_cap_to' p\<rbrace>"
  "\<lbrace>cur_tcb'\<rbrace> setMRs t buf mrs \<lbrace>\<lambda>rv. cur_tcb'\<rbrace>"
  "\<lbrace>if_unsafe_then_cap'\<rbrace> setMRs t buf mrs \<lbrace>\<lambda>rv. if_unsafe_then_cap'\<rbrace>"
  by (simp add: setMRs_def zipWithM_x_mapM split_def storeWordUser_def | wp crunch_wps)+

crunch no_0_obj'[wp]: setMRs no_0_obj'
  (wp: crunch_wps simp: crunch_simps)

lemma copyMRs_invs_bits[wp]:
  "\<lbrace>valid_pspace'\<rbrace> copyMRs s sb r rb n \<lbrace>\<lambda>rv. valid_pspace'\<rbrace>"
  "\<lbrace>\<lambda>s. sch_act_wf (ksSchedulerAction s) s\<rbrace> copyMRs s sb r rb n
      \<lbrace>\<lambda>rv s. sch_act_wf (ksSchedulerAction s) s\<rbrace>"
  "\<lbrace>Invariants_H.valid_queues\<rbrace> copyMRs s sb r rb n \<lbrace>\<lambda>rv. Invariants_H.valid_queues\<rbrace>"
  "\<lbrace>valid_queues'\<rbrace> copyMRs s sb r rb n \<lbrace>\<lambda>rv. valid_queues'\<rbrace>"
  "\<lbrace>\<lambda>s. P (state_refs_of' s)\<rbrace>
      copyMRs s sb r rb n
   \<lbrace>\<lambda>rv s. P (state_refs_of' s)\<rbrace>"
  "\<lbrace>if_live_then_nonz_cap'\<rbrace> copyMRs s sb r rb n \<lbrace>\<lambda>rv. if_live_then_nonz_cap'\<rbrace>"
  "\<lbrace>ex_nonz_cap_to' p\<rbrace> copyMRs s sb r rb n \<lbrace>\<lambda>rv. ex_nonz_cap_to' p\<rbrace>"
  "\<lbrace>cur_tcb'\<rbrace> copyMRs s sb r rb n \<lbrace>\<lambda>rv. cur_tcb'\<rbrace>"
  "\<lbrace>if_unsafe_then_cap'\<rbrace> copyMRs s sb r rb n \<lbrace>\<lambda>rv. if_unsafe_then_cap'\<rbrace>"
  by (simp add: copyMRs_def  storeWordUser_def | wp mapM_wp' | wpc)+

crunch no_0_obj'[wp]: copyMRs no_0_obj'
  (wp: crunch_wps simp: crunch_simps)

lemma mi_map_length[simp]: "msgLength (message_info_map mi) = mi_length mi"
  by (cases mi, simp)

crunch cte_wp_at'[wp]: copyMRs "cte_wp_at' P p"
  (wp: crunch_wps)

lemma lookupExtraCaps_srcs[wp]:
  "\<lbrace>\<top>\<rbrace> lookupExtraCaps thread buf info \<lbrace>transferCaps_srcs\<rbrace>,-"
  apply (simp add: lookupExtraCaps_def lookupCapAndSlot_def
                   split_def lookupSlotForThread_def
                   getSlotCap_def)
  apply (wp mapME_set[where R=\<top>] getCTE_wp')
       apply (rule_tac P=\<top> in hoare_trivE_R)
       apply (simp add: cte_wp_at_ctes_of)
      apply (wp | simp)+
  done

crunch inv[wp]: lookupExtraCaps "P"
  (wp: crunch_wps mapME_wp' simp: crunch_simps)

lemma invs_mdb_strengthen':
  "invs' s \<longrightarrow> valid_mdb' s" by auto

lemma lookupExtraCaps_length:
  "\<lbrace>\<lambda>s. unat (msgExtraCaps mi) \<le> n\<rbrace> lookupExtraCaps thread send_buf mi \<lbrace>\<lambda>rv s. length rv \<le> n\<rbrace>,-"
  apply (simp add: lookupExtraCaps_def getExtraCPtrs_def)
  apply (rule hoare_pre)
   apply (wp mapME_length | wpc)+
  apply (clarsimp simp: upto_enum_step_def Suc_unat_diff_1 word_le_sub1)
  done

lemma getMessageInfo_msgExtraCaps[wp]:
  "\<lbrace>\<top>\<rbrace> getMessageInfo t \<lbrace>\<lambda>rv s. unat (msgExtraCaps rv) \<le> msgMaxExtraCaps\<rbrace>"
  apply (simp add: getMessageInfo_def)
  apply wp
   apply (simp add: messageInfoFromWord_def Let_def msgMaxExtraCaps_def
                    shiftL_nat)
   apply (subst nat_le_Suc_less_imp)
    apply (rule unat_less_power)
     apply (simp add: word_bits_def msgExtraCapBits_def)
    apply (rule and_mask_less'[unfolded mask_2pm1])
    apply (simp add: msgExtraCapBits_def)
   apply wpsimp+
  done

lemma lcs_corres:
  "cptr = to_bl cptr' \<Longrightarrow>
  corres (lfr \<oplus> (\<lambda>a b. cap_relation (fst a) (fst b) \<and> snd b = cte_map (snd a)))
    (valid_objs and pspace_aligned and tcb_at thread)
    (valid_objs' and pspace_distinct' and pspace_aligned' and tcb_at' thread)
    (lookup_cap_and_slot thread cptr) (lookupCapAndSlot thread cptr')"
  unfolding lookup_cap_and_slot_def lookupCapAndSlot_def
  apply (simp add: liftE_bindE split_def)
  apply (rule corres_guard_imp)
    apply (rule_tac r'="\<lambda>rv rv'. rv' = cte_map (fst rv)"
                 in corres_splitEE)
       apply (rule corres_split[OF _ getSlotCap_corres])
          apply (rule corres_returnOkTT, simp)
         apply simp
        apply wp+
      apply (rule corres_rel_imp, rule lookup_slot_corres)
      apply (simp add: split_def)
     apply (wp | simp add: liftE_bindE[symmetric])+
  done

lemma lec_corres:
  "\<lbrakk> info' = message_info_map info; buffer = buffer'\<rbrakk> \<Longrightarrow>
  corres (fr \<oplus> list_all2 (\<lambda>x y. cap_relation (fst x) (fst y) \<and> snd y = cte_map (snd x)))
   (valid_objs and pspace_aligned and tcb_at thread and (\<lambda>_. valid_message_info info))
   (valid_objs' and pspace_distinct' and pspace_aligned' and tcb_at' thread
        and case_option \<top> valid_ipc_buffer_ptr' buffer')
   (lookup_extra_caps thread buffer info) (lookupExtraCaps thread buffer' info')"
  unfolding lookupExtraCaps_def lookup_extra_caps_def
  apply (rule corres_gen_asm)
  apply (cases "mi_extra_caps info = 0")
   apply (cases info)
   apply (simp add: Let_def returnOk_def getExtraCPtrs_def
                    liftE_bindE upto_enum_step_def mapM_def
                    sequence_def doMachineOp_return mapME_Nil
             split: option.split)
  apply (cases info)
  apply (rename_tac w1 w2 w3 w4)
  apply (simp add: Let_def liftE_bindE)
  apply (cases buffer')
   apply (simp add: getExtraCPtrs_def mapME_Nil)
   apply (rule corres_returnOk)
   apply simp
  apply (simp add: msgLengthBits_def msgMaxLength_def word_size field_simps
                   getExtraCPtrs_def upto_enum_step_def upto_enum_word
                   word_size_def msg_max_length_def liftM_def
                   Suc_unat_diff_1 word_le_sub1 mapM_map_simp
                   upt_lhs_sub_map[where x=buffer_cptr_index]
                   wordSize_def wordBits_def
              del: upt.simps)
  apply (rule corres_guard_imp)
    apply (rule corres_split')

       apply (rule_tac S = "\<lambda>x y. x = y \<and> x < unat w2"
               in corres_mapM_list_all2
         [where Q = "\<lambda>_. valid_objs and pspace_aligned and tcb_at thread" and r = "(=)"
            and Q' = "\<lambda>_. valid_objs' and pspace_aligned' and pspace_distinct' and tcb_at' thread
              and case_option \<top> valid_ipc_buffer_ptr' buffer'" and r'="(=)" ])
            apply simp
           apply simp
          apply simp
          apply (rule corres_guard_imp)
            apply (rule load_word_offs_corres')
             apply (clarsimp simp: buffer_cptr_index_def msg_max_length_def
                                   max_ipc_words valid_message_info_def
                                   msg_max_extra_caps_def word_le_nat_alt)
            apply (simp add: buffer_cptr_index_def msg_max_length_def)
           apply simp
          apply simp
         apply (simp add: load_word_offs_word_def)
         apply (wp | simp)+
       apply (subst list_all2_same)
       apply (clarsimp simp: max_ipc_words field_simps)
      apply (simp add: mapME_def, fold mapME_def)[1]
      apply (rule corres_mapME [where S = Id and r'="(\<lambda>x y. cap_relation (fst x) (fst y) \<and> snd y = cte_map (snd x))"])
            apply simp
           apply simp
          apply simp
          apply (rule corres_cap_fault [OF lcs_corres])
          apply simp
         apply simp
         apply (wp | simp)+
      apply (simp add: set_zip_same Int_lower1)
     apply (wp mapM_wp [OF _ subset_refl] | simp)+
  done

crunch ctes_of[wp]: copyMRs "\<lambda>s. P (ctes_of s)"
  (wp: threadSet_ctes_of crunch_wps)

lemma copyMRs_valid_mdb[wp]:
  "\<lbrace>valid_mdb'\<rbrace> copyMRs t buf t' buf' n \<lbrace>\<lambda>rv. valid_mdb'\<rbrace>"
  by (simp add: valid_mdb'_def copyMRs_ctes_of)

lemma do_normal_transfer_corres:
  "corres dc
  (tcb_at sender and tcb_at receiver and (pspace_aligned:: det_state \<Rightarrow> bool)
   and valid_objs and cur_tcb and valid_mdb and valid_list and pspace_distinct
   and (\<lambda>s. case ep of Some x \<Rightarrow> ep_at x s | _ \<Rightarrow> True)
   and case_option \<top> in_user_frame send_buf
   and case_option \<top> in_user_frame recv_buf)
  (tcb_at' sender and tcb_at' receiver and valid_objs'
   and pspace_aligned' and pspace_distinct' and cur_tcb'
   and valid_mdb' and no_0_obj'
   and (\<lambda>s. case ep of Some x \<Rightarrow> ep_at' x s | _ \<Rightarrow> True)
   and case_option \<top> valid_ipc_buffer_ptr' send_buf
   and case_option \<top> valid_ipc_buffer_ptr' recv_buf)
  (do_normal_transfer sender send_buf ep badge can_grant receiver recv_buf)
  (doNormalTransfer sender send_buf ep badge can_grant receiver recv_buf)"
  apply (simp add: do_normal_transfer_def doNormalTransfer_def)
  apply (rule corres_guard_imp)

    apply (rule corres_split_mapr [OF _ get_mi_corres])
      apply (rule_tac F="valid_message_info mi" in corres_gen_asm)
      apply (rule_tac r'="list_all2 (\<lambda>x y. cap_relation (fst x) (fst y) \<and> snd y = cte_map (snd x))"
                  in corres_split)
         prefer 2
         apply (rule corres_if[OF refl])
          apply (rule corres_split_catch)
             apply (rule corres_trivial, simp)
            apply (rule lec_corres, simp+)
           apply wp+
         apply (rule corres_trivial, simp)
        apply simp
        apply (rule corres_split_eqr [OF _ copy_mrs_corres])
          apply (rule corres_split [OF _ tc_corres])
              apply (rename_tac mi' mi'')
              apply (rule_tac F="mi_label mi' = mi_label mi"
                        in corres_gen_asm)
              apply (rule corres_split_nor [OF _ set_mi_corres])
                 apply (simp add: badge_register_def badgeRegister_def)
                 apply (fold dc_def)
                 apply (rule user_setreg_corres)
                apply (case_tac mi', clarsimp)
               apply wp
             apply simp+
           apply ((wp valid_case_option_post_wp hoare_vcg_const_Ball_lift
                     hoare_case_option_wp
                     hoare_valid_ipc_buffer_ptr_typ_at' copyMRs_typ_at'
                     hoare_vcg_const_Ball_lift lookupExtraCaps_length
                   | simp add: if_apply_def2)+)
      apply (wp static_imp_wp | strengthen valid_msg_length_strengthen)+
   apply clarsimp
  apply auto
  done

lemma corres_liftE_lift:
  "corres r1 P P' m m' \<Longrightarrow>
  corres (f1 \<oplus> r1) P P' (liftE m) (withoutFailure m')"
  by simp

lemmas corres_ipc_thread_helper =
  corres_split_eqrE [OF _  corres_liftE_lift [OF gct_corres]]

lemmas corres_ipc_info_helper =
  corres_split_maprE [where f = message_info_map, OF _
                                corres_liftE_lift [OF get_mi_corres]]

crunch typ_at'[wp]: doNormalTransfer "\<lambda>s. P (typ_at' T p s)"

lemmas doNormal_lifts[wp] = typ_at_lifts [OF doNormalTransfer_typ_at']

lemma doNormal_invs'[wp]:
  "\<lbrace>tcb_at' sender and tcb_at' receiver and invs'\<rbrace>
    doNormalTransfer sender send_buf ep badge
             can_grant receiver recv_buf \<lbrace>\<lambda>r. invs'\<rbrace>"
  apply (simp add: doNormalTransfer_def)
  apply (wp hoare_vcg_const_Ball_lift | simp)+
  done

crunch aligned'[wp]: doNormalTransfer pspace_aligned'
  (wp: crunch_wps)
crunch distinct'[wp]: doNormalTransfer pspace_distinct'
  (wp: crunch_wps)

lemma transferCaps_urz[wp]:
  "\<lbrace>untyped_ranges_zero' and valid_pspace'
      and (\<lambda>s. (\<forall>x\<in>set caps. cte_wp_at' (\<lambda>cte. fst x \<noteq> capability.NullCap \<longrightarrow> cteCap cte = fst x) (snd x) s))\<rbrace>
    transferCaps tag caps ep receiver recv_buf
  \<lbrace>\<lambda>r. untyped_ranges_zero'\<rbrace>"
  apply (simp add: transferCaps_def)
  apply (rule hoare_pre)
   apply (wp hoare_vcg_all_lift hoare_vcg_const_imp_lift
      | wpc
      | simp add: ball_conj_distrib)+
  apply clarsimp
  done

crunch gsUntypedZeroRanges[wp]: doNormalTransfer "\<lambda>s. P (gsUntypedZeroRanges s)"
  (wp: crunch_wps transferCapsToSlots_pres1 ignore: constOnFailure)

lemmas asUser_urz = untyped_ranges_zero_lift[OF asUser_gsUntypedZeroRanges]

crunch urz[wp]: doNormalTransfer "untyped_ranges_zero'"
  (ignore: asUser wp: crunch_wps asUser_urz hoare_vcg_const_Ball_lift)

lemma msgFromLookupFailure_map[simp]:
  "msgFromLookupFailure (lookup_failure_map lf)
     = msg_from_lookup_failure lf"
  by (cases lf, simp_all add: lookup_failure_map_def msgFromLookupFailure_def)

lemma getRestartPCs_corres:
  "corres (=) (tcb_at t) (tcb_at' t)
                 (as_user t getRestartPC) (asUser t getRestartPC)"
  apply (rule corres_as_user')
  apply (rule corres_Id, simp, simp)
  apply (rule no_fail_getRestartPC)
  done

lemma user_mapM_getRegister_corres:
  "corres (=) (tcb_at t) (tcb_at' t)
     (as_user t (mapM getRegister regs))
     (asUser t (mapM getRegister regs))"
  apply (rule corres_as_user')
  apply (rule corres_Id [OF refl refl])
  apply (rule no_fail_mapM)
  apply (simp add: getRegister_def)
  done

lemma make_arch_fault_msg_corres:
  "corres (=) (tcb_at t) (tcb_at' t)
  (make_arch_fault_msg f t)
  (makeArchFaultMessage (arch_fault_map f) t)"
  apply (cases f, clarsimp simp: makeArchFaultMessage_def split: arch_fault.split)
  apply (rule corres_guard_imp)
    apply (rule corres_split_eqr[OF _ getRestartPCs_corres])
      apply (rule corres_trivial, simp add: arch_fault_map_def)
     apply (wp+, auto)
  done

lemma mk_ft_msg_corres:
  "corres (=) (tcb_at t) (tcb_at' t)
     (make_fault_msg ft t)
     (makeFaultMessage (fault_map ft) t)"
  apply (cases ft, simp_all add: makeFaultMessage_def split del: if_split)
     apply (rule corres_guard_imp)
       apply (rule corres_split_eqr [OF _ getRestartPCs_corres])
         apply (rule corres_trivial, simp add: fromEnum_def enum_bool)
        apply (wp | simp)+
    apply (simp add: ARM_H.syscallMessage_def)
    apply (rule corres_guard_imp)
      apply (rule corres_split_eqr [OF _ user_mapM_getRegister_corres])
        apply (rule corres_trivial, simp)
       apply (wp | simp)+
   apply (simp add: ARM_H.exceptionMessage_def)
   apply (rule corres_guard_imp)
     apply (rule corres_split_eqr [OF _ user_mapM_getRegister_corres])
       apply (rule corres_trivial, simp)
      apply (wp | simp)+
  sorry (*
  apply (rule make_arch_fault_msg_corres)
  done *)

crunches makeFaultMessage
  for typ_at'[wp]: "\<lambda>s. P (typ_at' T p s)"

lemmas makeFaultMessage_typ_ats'[wp] = typ_at_lifts[OF makeFaultMessage_typ_at']

lemmas threadget_fault_corres =
          threadget_corres [where r = fault_rel_optionation
                              and f = tcb_fault and f' = tcbFault,
                            simplified tcb_relation_def, simplified]

lemma do_fault_transfer_corres:
  "corres dc
    (obj_at (\<lambda>ko. \<exists>tcb ft. ko = TCB tcb \<and> tcb_fault tcb = Some ft) sender
     and tcb_at receiver and case_option \<top> in_user_frame recv_buf)
    (tcb_at' sender and tcb_at' receiver and
     case_option \<top> valid_ipc_buffer_ptr' recv_buf)
    (do_fault_transfer badge sender receiver recv_buf)
    (doFaultTransfer badge sender receiver recv_buf)"
  apply (clarsimp simp: do_fault_transfer_def doFaultTransfer_def split_def
                        ARM_H.badgeRegister_def badge_register_def)
  apply (rule_tac Q="\<lambda>fault. K (\<exists>f. fault = Some f) and
                             tcb_at sender and tcb_at receiver and
                             case_option \<top> in_user_frame recv_buf"
              and Q'="\<lambda>fault'. tcb_at' sender and tcb_at' receiver and
                               case_option \<top> valid_ipc_buffer_ptr' recv_buf"
               in corres_split')
     apply (rule corres_guard_imp)
       apply (rule threadget_fault_corres)
      apply (clarsimp simp: obj_at_def is_tcb)+
    apply (rule corres_assume_pre)
    apply (fold assert_opt_def | unfold haskell_fail_def)+
    apply (rule corres_assert_opt_assume)
     apply (clarsimp split: option.splits
                      simp: fault_rel_optionation_def assert_opt_def
                            map_option_case)
     defer
     defer
     apply (clarsimp simp: fault_rel_optionation_def)
    apply (wp thread_get_wp)
    apply (clarsimp simp: obj_at_def is_tcb)
   apply wp
   apply (rule corres_guard_imp)
      apply (rule corres_split_eqr [OF _ mk_ft_msg_corres])
        apply (rule corres_split_eqr [OF _ set_mrs_corres [OF refl]])
          apply (rule corres_split_nor [OF _ set_mi_corres])
             apply (rule user_setreg_corres)
            apply simp
           apply (wp | simp)+
   apply (rule corres_guard_imp)
      apply (rule corres_split_eqr [OF _ mk_ft_msg_corres])
        apply (rule corres_split_eqr [OF _ set_mrs_corres [OF refl]])
          apply (rule corres_split_nor [OF _ set_mi_corres])
             apply (rule user_setreg_corres)
            apply simp
           apply (wp | simp)+
  sorry

lemma doFaultTransfer_invs[wp]:
  "\<lbrace>invs' and tcb_at' receiver\<rbrace>
      doFaultTransfer badge sender receiver recv_buf
   \<lbrace>\<lambda>rv. invs'\<rbrace>"
  sorry (*
  by (simp add: doFaultTransfer_def split_def | wp
    | clarsimp split: option.split)+ *)

lemma lookupIPCBuffer_valid_ipc_buffer [wp]:
  "\<lbrace>valid_objs'\<rbrace> VSpace_H.lookupIPCBuffer b s \<lbrace>case_option \<top> valid_ipc_buffer_ptr'\<rbrace>"
  unfolding lookupIPCBuffer_def ARM_H.lookupIPCBuffer_def
  apply (simp add: Let_def getSlotCap_def getThreadBufferSlot_def
                   locateSlot_conv threadGet_def comp_def)
  apply (wp getCTE_wp getObject_tcb_wp | wpc)+
  apply (clarsimp simp del: imp_disjL)
  apply (drule obj_at_ko_at')
  apply (clarsimp simp del: imp_disjL)
  apply (rule_tac x = ko in exI)
  apply (frule ko_at_cte_ipcbuffer)
  apply (clarsimp simp: cte_wp_at_ctes_of simp del: imp_disjL)
  apply (clarsimp simp: valid_ipc_buffer_ptr'_def)
  apply (frule (1) ko_at_valid_objs')
   apply (clarsimp simp: projectKO_opts_defs split: kernel_object.split_asm)
  apply (clarsimp simp add: valid_obj'_def valid_tcb'_def
                            isCap_simps cte_level_bits_def field_simps)
  apply (drule bspec [OF _ ranI [where a = "0x20"]])
   apply simp
  apply (clarsimp simp add: valid_cap'_def)
  apply (rule conjI)
   apply (rule aligned_add_aligned)
     apply (clarsimp simp add: capAligned_def)
     apply assumption
    apply (erule is_aligned_andI1)
   apply (case_tac xd, simp_all add: msg_align_bits)[1]
  apply (clarsimp simp: capAligned_def)
  apply (drule_tac x =
    "(tcbIPCBuffer ko && mask (pageBitsForSize xd))  >> pageBits" in spec)
  apply (subst(asm) mult.commute mult.left_commute, subst(asm) shiftl_t2n[symmetric])
  apply (simp add: shiftr_shiftl1)
  apply (subst (asm) mask_out_add_aligned)
   apply (erule is_aligned_weaken [OF _ pbfs_atleast_pageBits])
  apply (erule mp)
  apply (rule shiftr_less_t2n)
  apply (clarsimp simp: pbfs_atleast_pageBits)
  apply (rule and_mask_less')
  apply (simp add: word_bits_conv)
  done

lemma dit_corres:
  "corres dc
     (tcb_at s and tcb_at r and valid_objs and pspace_aligned
        and valid_list
        and pspace_distinct and valid_mdb and cur_tcb
        and (\<lambda>s. case ep of Some x \<Rightarrow> ep_at x s | _ \<Rightarrow> True))
     (tcb_at' s and tcb_at' r and valid_pspace' and cur_tcb'
        and (\<lambda>s. case ep of Some x \<Rightarrow> ep_at' x s | _ \<Rightarrow> True))
     (do_ipc_transfer s ep bg grt r)
     (doIPCTransfer s ep bg grt r)"
  apply (simp add: do_ipc_transfer_def doIPCTransfer_def)
  apply (rule_tac Q="%receiveBuffer sa. tcb_at s sa \<and> valid_objs sa \<and>
                       pspace_aligned sa \<and> tcb_at r sa \<and>
                       cur_tcb sa \<and> valid_mdb sa \<and> valid_list sa \<and> pspace_distinct sa \<and>
                       (case ep of None \<Rightarrow> True | Some x \<Rightarrow> ep_at x sa) \<and>
                       case_option (\<lambda>_. True) in_user_frame receiveBuffer sa \<and>
                       obj_at (\<lambda>ko. \<exists>tcb. ko = TCB tcb
                                    \<comment> \<open>\<exists>ft. tcb_fault tcb = Some ft\<close>) s sa"
               in corres_split')
     apply (rule corres_guard_imp)
       apply (rule lipcb_corres')
      apply auto[2]
    apply (rule corres_split' [OF _ _ thread_get_sp threadGet_inv])
     apply (rule corres_guard_imp)
       apply (rule threadget_fault_corres)
      apply simp
     defer
     apply (rule corres_guard_imp)
       apply (subst case_option_If)+
       apply (rule corres_if2)
         apply (simp add: fault_rel_optionation_def)
        apply (rule corres_split_eqr [OF _ lipcb_corres'])
          apply (simp add: dc_def[symmetric])
          apply (rule do_normal_transfer_corres)
         apply (wp | simp add: valid_pspace'_def)+
       apply (simp add: dc_def[symmetric])
       apply (rule do_fault_transfer_corres)
      apply (clarsimp simp: obj_at_def)
     apply (erule ignore_if)
    apply (wp|simp add: obj_at_def is_tcb valid_pspace'_def)+
  done

lemma setSchedContext_idle':
  "\<lbrace>\<lambda>s. p \<noteq> ksIdleThread s \<and> valid_idle' s\<rbrace> setSchedContext p sc \<lbrace>\<lambda>_. valid_idle'\<rbrace>"
  sorry

lemma setSchedContext_pde_mappings':
  "setSchedContext p sc \<lbrace>valid_pde_mappings'\<rbrace>"
  sorry

lemma makeFaultMessage_iflive:
  "makeFaultMessage f t \<lbrace>if_live_then_nonz_cap'\<rbrace>"
  sorry

lemma makeFaultMessage_idle':
  "makeFaultMessage f t \<lbrace>valid_idle'\<rbrace>"
  sorry

lemma schedContextUpdateConsumed_state_refs_of:
  "schedContextUpdateConsumed sc \<lbrace>\<lambda>s. P (state_refs_of' s)\<rbrace>"
  unfolding schedContextUpdateConsumed_def
  sorry

lemma schedContextUpdateConsumed_objs':
  "schedContextUpdateConsumed sc \<lbrace>valid_objs'\<rbrace>"
  sorry


crunches doIPCTransfer
  for ifunsafe[wp]: "if_unsafe_then_cap'"
  and iflive[wp]: "if_live_then_nonz_cap'"
  and sch_act_wf[wp]: "\<lambda>s. sch_act_wf (ksSchedulerAction s) s"
  and vq[wp]: "valid_queues"
  and vq'[wp]: "valid_queues'"
  and state_refs_of[wp]: "\<lambda>s. P (state_refs_of' s)"
  and ct[wp]: "cur_tcb'"
  and idle'[wp]: "valid_idle'"
  and typ_at'[wp]: "\<lambda>s. P (typ_at' T p s)"
  and irq_node'[wp]: "\<lambda>s. P (irq_node' s)"
  and valid_arch_state'[wp]: "valid_arch_state'"
  (wp: crunch_wps
   simp: zipWithM_x_mapM ball_conj_distrib )

lemmas dit'_typ_ats[wp] = typ_at_lifts [OF doIPCTransfer_typ_at']
lemmas dit_irq_node'[wp] = valid_irq_node_lift [OF doIPCTransfer_irq_node' doIPCTransfer_typ_at']

declare asUser_global_refs' [wp]

lemma lec_valid_cap' [wp]:
  "\<lbrace>valid_objs'\<rbrace> lookupExtraCaps thread xa mi \<lbrace>\<lambda>rv s. (\<forall>x\<in>set rv. s \<turnstile>' fst x)\<rbrace>, -"
  apply (rule hoare_pre, rule hoare_post_imp_R)
    apply (rule hoare_vcg_conj_lift_R[where R=valid_objs' and S="\<lambda>_. valid_objs'"])
     apply (rule lookupExtraCaps_srcs)
    apply wp
   apply (clarsimp simp: cte_wp_at_ctes_of)
   apply (fastforce)
  apply simp
  done

declare asUser_irq_handlers'[wp]

crunches doIPCTransfer
  for sc_at'_n[wp]: "sc_at'_n n p"
  and objs'[wp]: "valid_objs'"
  and global_refs'[wp]: "valid_global_refs'"
  and irq_handlers'[wp]: "valid_irq_handlers'"
  and irq_states'[wp]: "valid_irq_states'"
  and pde_mappings'[wp]: "valid_pde_mappings'"
  and irqs_masked'[wp]: "irqs_masked'"
  (wp: crunch_wps hoare_vcg_const_Ball_lift
   simp: zipWithM_x_mapM ball_conj_distrib
   rule: irqs_masked_lift)

lemma doIPCTransfer_invs[wp]:
  "\<lbrace>invs' and tcb_at' s and tcb_at' r\<rbrace>
   doIPCTransfer s ep bg grt r
   \<lbrace>\<lambda>rv. invs'\<rbrace>"
  apply (simp add: doIPCTransfer_def)
  apply (wpsimp wp: hoare_drop_imp)
  done

lemma handle_fault_reply_registers_corres:
  "corres (=) (tcb_at t) (tcb_at' t)
           (do t' \<leftarrow> arch_get_sanitise_register_info t;
               y \<leftarrow> as_user t
                (zipWithM_x
                  (\<lambda>r v. setRegister r
                          (sanitise_register t' r v))
                  msg_template msg);
               return (label = 0)
            od)
           (do t' \<leftarrow> getSanitiseRegisterInfo t;
               y \<leftarrow> asUser t
                (zipWithM_x
                  (\<lambda>r v. setRegister r (sanitiseRegister t' r v))
                  msg_template msg);
               return (label = 0)
            od)"
  apply (rule corres_guard_imp)
    apply (clarsimp simp: arch_get_sanitise_register_info_def getSanitiseRegisterInfo_def)
       apply (rule corres_split)
       apply (rule corres_trivial, simp)
      apply (rule corres_as_user')
      apply(simp add: setRegister_def sanitise_register_def
                      sanitiseRegister_def syscallMessage_def)
      apply(subst zipWithM_x_modify)+
      apply(rule corres_modify')
       apply (simp|wp)+
  done

lemma handle_fault_reply_corres:
  "ft' = fault_map ft \<Longrightarrow>
   corres (=) (tcb_at t) (tcb_at' t)
          (handle_fault_reply ft t label msg)
          (handleFaultReply ft' t label msg)"
  apply (cases ft; simp add: handleFaultReply_def handle_arch_fault_reply_def
                             handleArchFaultReply_def syscallMessage_def exceptionMessage_def
                        split: arch_fault.split)
  by (rule handle_fault_reply_registers_corres)+

crunches handleFaultReply
  for typ_at'[wp]: "\<lambda>s. P (typ_at' T p s)"
  and ct'[wp]: "\<lambda>s. P (ksCurThread s)"

lemmas hfr_typ_ats[wp] = typ_at_lifts [OF handleFaultReply_typ_at']

lemma doIPCTransfer_sch_act_simple [wp]:
  "\<lbrace>sch_act_simple\<rbrace> doIPCTransfer sender endpoint badge grant receiver \<lbrace>\<lambda>_. sch_act_simple\<rbrace>"
  by (simp add: sch_act_simple_def, wp)

lemma possibleSwitchTo_invs'[wp]:
  "\<lbrace>invs' and st_tcb_at' runnable' t
          and (\<lambda>s. ksSchedulerAction s = ResumeCurrentThread \<longrightarrow> ksCurThread s \<noteq> t)\<rbrace>
   possibleSwitchTo t \<lbrace>\<lambda>_. invs'\<rbrace>"
  apply (simp add: possibleSwitchTo_def curDomain_def inReleaseQueue_def)
  apply (wp tcbSchedEnqueue_invs' ssa_invs')
       apply (rule hoare_post_imp[OF _ rescheduleRequired_sa_cnt])
      apply (wpsimp wp: ssa_invs' threadGet_wp)+
  apply (clarsimp dest!: obj_at_ko_at' simp: tcb_in_cur_domain'_def obj_at'_def)
  sorry

crunches isFinalCapability
  for cur' [wp]: "\<lambda>s. P (cur_tcb' s)"
  (simp: crunch_simps unless_when
     wp: crunch_wps getObject_inv loadObject_default_inv)

lemma finaliseCapTrue_standin_tcb_at' [wp]:
  "\<lbrace>tcb_at' x\<rbrace> finaliseCapTrue_standin cap v2 \<lbrace>\<lambda>_. tcb_at' x\<rbrace>"
  by (rule finaliseCapTrue_standin_tcbDomain_obj_at')

crunches finaliseCapTrue_standin
  for ct'[wp]: "\<lambda>s. P (ksCurThread s)"
  (wp: crunch_wps simp: crunch_simps)

lemma finaliseCapTrue_standin_cur':
  "\<lbrace>\<lambda>s. cur_tcb' s\<rbrace> finaliseCapTrue_standin cap v2 \<lbrace>\<lambda>_ s'. cur_tcb' s'\<rbrace>"
  unfolding cur_tcb'_def
  by (wp_pre, wps, wp, assumption)

lemma cteDeleteOne_cur' [wp]:
  "\<lbrace>\<lambda>s. cur_tcb' s\<rbrace> cteDeleteOne slot \<lbrace>\<lambda>_ s'. cur_tcb' s'\<rbrace>"
  apply (simp add: cteDeleteOne_def unless_def when_def)
  apply (wp hoare_drop_imps finaliseCapTrue_standin_cur' isFinalCapability_cur'
         | simp add: split_def | wp (once) cur_tcb_lift)+
  done

lemma handleFaultReply_cur' [wp]:
  "\<lbrace>\<lambda>s. cur_tcb' s\<rbrace> handleFaultReply x0 thread label msg \<lbrace>\<lambda>_ s'. cur_tcb' s'\<rbrace>"
  apply (clarsimp simp add: cur_tcb'_def)
  apply (rule hoare_lift_Pf2 [OF _ handleFaultReply_ct'])
  apply (wp)
  done

lemma replyClear_valid_objs'[wp]:
  "replyClear r t \<lbrace>valid_objs'\<rbrace>"
  sorry

lemma schedContextUnbindNtfn_valid_objs'[wp]:
  "schedContextUnbindNtfn sc \<lbrace>valid_objs'\<rbrace>"
  sorry

crunches cteDeleteOne
  for valid_objs'[wp]: "valid_objs'"
  (simp: crunch_simps unless_def
   wp: crunch_wps getObject_inv loadObject_default_inv)

crunches handleFaultReply
  for nosch[wp]: "\<lambda>s. P (ksSchedulerAction s)"

lemma emptySlot_weak_sch_act[wp]:
  "\<lbrace>\<lambda>s. weak_sch_act_wf (ksSchedulerAction s) s\<rbrace>
   emptySlot slot irq
   \<lbrace>\<lambda>_ s. weak_sch_act_wf (ksSchedulerAction s) s\<rbrace>"
  by (wp weak_sch_act_wf_lift tcb_in_cur_domain'_lift)

lemma cancelAllIPC_weak_sch_act_wf[wp]:
  "\<lbrace>\<lambda>s. weak_sch_act_wf (ksSchedulerAction s) s\<rbrace>
   cancelAllIPC epptr
   \<lbrace>\<lambda>_ s. weak_sch_act_wf (ksSchedulerAction s) s\<rbrace>"
  apply (simp add: cancelAllIPC_def)
  apply (wp rescheduleRequired_weak_sch_act_wf hoare_drop_imp | wpc | simp)+
  done

lemma cancelAllSignals_weak_sch_act_wf[wp]:
  "\<lbrace>\<lambda>s. weak_sch_act_wf (ksSchedulerAction s) s\<rbrace>
   cancelAllSignals ntfnptr
   \<lbrace>\<lambda>_ s. weak_sch_act_wf (ksSchedulerAction s) s\<rbrace>"
  apply (simp add: cancelAllSignals_def)
  apply (wp rescheduleRequired_weak_sch_act_wf hoare_drop_imp | wpc | simp)+
  done

lemma setSchedContext_weak_sch_act_wf:
  "setSchedContext p sc \<lbrace> \<lambda>s. weak_sch_act_wf (ksSchedulerAction s) s \<rbrace>"
  sorry

lemma setReply_weak_sch_act_wf:
  "setReply p r \<lbrace> \<lambda>s. weak_sch_act_wf (ksSchedulerAction s) s \<rbrace>"
  sorry

crunches replyUnlink
  for nosch[wp]: "\<lambda>s. P (ksSchedulerAction s)"
  (simp: crunch_simps wp: crunch_wps)

lemma replyUnlink_weak_sch_act_wf[wp]:
  "replyUnlink r t \<lbrace> \<lambda>s. weak_sch_act_wf (ksSchedulerAction s) s \<rbrace>"
  sorry

crunches finaliseCapTrue_standin
  for weak_sch_act_wf[wp]: "\<lambda>s. weak_sch_act_wf (ksSchedulerAction s) s"
  (simp: crunch_simps wp: crunch_wps)

lemma cteDeleteOne_weak_sch_act[wp]:
  "\<lbrace>\<lambda>s. weak_sch_act_wf (ksSchedulerAction s) s\<rbrace>
   cteDeleteOne sl
   \<lbrace>\<lambda>_ s. weak_sch_act_wf (ksSchedulerAction s) s\<rbrace>"
  apply (simp add: cteDeleteOne_def unless_def)
  apply (wp hoare_drop_imps finaliseCapTrue_standin_cur' isFinalCapability_cur'
         | simp add: split_def)+
  done

crunches handleFaultReply
  for pred_tcb_at'[wp]: "pred_tcb_at' proj P t"
  and valid_queues[wp]: "Invariants_H.valid_queues"
  and valid_queues'[wp]: "valid_queues'"
  and tcb_in_cur_domain'[wp]: "tcb_in_cur_domain' t"

crunches unbindNotification
  for sch_act_wf[wp]: "\<lambda>s. sch_act_wf (ksSchedulerAction s) s"
  (wp: sbn_sch_act')

lemma possibleSwitchTo_valid_queues[wp]:
  "\<lbrace>Invariants_H.valid_queues and valid_objs' and
    (\<lambda>s. sch_act_wf (ksSchedulerAction s) s) and st_tcb_at' runnable' t\<rbrace>
   possibleSwitchTo t
   \<lbrace>\<lambda>rv. Invariants_H.valid_queues\<rbrace>"
  apply (simp add: possibleSwitchTo_def curDomain_def bitmap_fun_defs)
  apply (wp hoare_drop_imps | wpc | simp)+
  apply (auto simp: valid_tcb'_def weak_sch_act_wf_def
              dest: pred_tcb_at'
             elim!: valid_objs_valid_tcbE)
  sorry


lemma possibleSwitchTo_valid_queues'[wp]:
  "\<lbrace>valid_queues' and (\<lambda>s. sch_act_wf (ksSchedulerAction s) s)
                  and st_tcb_at' runnable' t\<rbrace>
   possibleSwitchTo t
   \<lbrace>\<lambda>rv. valid_queues'\<rbrace>"
  apply (simp add: possibleSwitchTo_def curDomain_def bitmap_fun_defs)
  apply (wp static_imp_wp threadGet_wp | wpc | simp)+
  apply (auto simp: obj_at'_def)
  sorry


lemma possibleSwitchTo_weak_sch_act_wf[wp]:
  "\<lbrace>\<lambda>s. weak_sch_act_wf (ksSchedulerAction s) s \<and> st_tcb_at' runnable' t s\<rbrace>
   possibleSwitchTo t
   \<lbrace>\<lambda>rv s. weak_sch_act_wf (ksSchedulerAction s) s\<rbrace>"
  apply (simp add: possibleSwitchTo_def setSchedulerAction_def threadGet_def curDomain_def
                   bitmap_fun_defs)
  apply (wp rescheduleRequired_weak_sch_act_wf
            weak_sch_act_wf_lift_linear[where f="tcbSchedEnqueue t"]
            getObject_tcb_wp static_imp_wp
           | wpc)+
  apply (clarsimp simp: obj_at'_def projectKOs weak_sch_act_wf_def ps_clear_def tcb_in_cur_domain'_def)
  sorry

lemma replyUnlink_sch_act_no[wp]:
  "replyUnlink r t' \<lbrace> sch_act_not t \<rbrace>"
  by wpsimp

lemma schedContextDonate_valid_queues':
  "schedContextDonate sc t \<lbrace> valid_queues' \<rbrace>"
  sorry

lemma cancelAllIPC_valid_queues':
  "cancelAllIPC t \<lbrace> valid_queues' \<rbrace>"
  sorry

lemma cancelAllSignals_valid_queues':
  "cancelAllSignals t \<lbrace> valid_queues' \<rbrace>"
  sorry

crunches cteDeleteOne
  for valid_queues'[wp]: valid_queues'
  (simp: crunch_simps inQ_def
     wp: crunch_wps sts_st_tcb' getObject_inv loadObject_default_inv
         threadSet_valid_queues' rescheduleRequired_valid_queues'_weak)

lemma cancelSignal_valid_queues'[wp]:
  "\<lbrace>valid_queues'\<rbrace> cancelSignal t ntfn \<lbrace>\<lambda>rv. valid_queues'\<rbrace>"
  apply (simp add: cancelSignal_def)
  apply (rule hoare_pre)
   apply (wp getNotification_wp| wpc | simp)+
  done

lemma cancelIPC_valid_queues'[wp]:
  "\<lbrace>valid_queues' and (\<lambda>s. sch_act_wf (ksSchedulerAction s) s) \<rbrace> cancelIPC t \<lbrace>\<lambda>rv. valid_queues'\<rbrace>"
  apply (simp add: cancelIPC_def Let_def locateSlot_conv liftM_def)
  sorry (*
  apply (rule hoare_seq_ext[OF _ gts_sp'])
  apply (case_tac state, simp_all) defer 2
  apply (rule hoare_pre)
   apply ((wp getEndpoint_wp getCTE_wp | wpc | simp)+)[8]
  apply (wp cteDeleteOne_valid_queues')
  apply (rule_tac Q="\<lambda>_. valid_queues' and (\<lambda>s. sch_act_wf (ksSchedulerAction s) s)" in hoare_post_imp)
  apply (clarsimp simp: capHasProperty_def cte_wp_at_ctes_of)
   apply (wp threadSet_valid_queues' threadSet_sch_act| simp)+
  apply (clarsimp simp: inQ_def)
  done *)

crunches handleFaultReply
  for valid_objs'[wp]: valid_objs'

lemma valid_tcb'_tcbFault_update[simp]: "\<And>tcb s. valid_tcb' tcb s \<Longrightarrow> valid_tcb' (tcbFault_update f tcb) s"
  by (clarsimp simp: valid_tcb'_def  tcb_cte_cases_def)

lemma do_reply_transfer_corres:
  "corres dc
     (einvs and reply_at reply and tcb_at sender)
     (invs')
     (do_reply_transfer sender reply grant)
     (doReplyTransfer sender reply grant)"
  apply (simp add: do_reply_transfer_def doReplyTransfer_def cong: option.case_cong)
  sorry (*
  apply (rule corres_split' [OF _ _ gts_sp gts_sp'])
   apply (rule corres_guard_imp)
     apply (rule gts_corres, (clarsimp simp add: st_tcb_at_tcb_at)+)
  apply (rule_tac F = "awaiting_reply state" in corres_req)
   apply (clarsimp simp add: st_tcb_at_def obj_at_def is_tcb)
   apply (fastforce simp: invs_def valid_state_def intro: has_reply_cap_cte_wpD
                   dest: has_reply_cap_cte_wpD
                  dest!: valid_reply_caps_awaiting_reply cte_wp_at_is_reply_cap_toI)
  apply (case_tac state, simp_all add: bind_assoc)
  apply (simp add: isReply_def liftM_def)
  apply (rule corres_symb_exec_r[OF _ getCTE_sp getCTE_inv, rotated])
   apply (rule no_fail_pre, wp)
   apply clarsimp
  apply (rename_tac mdbnode)
  apply (rule_tac P="Q" and Q="Q" and P'="Q'" and Q'="(\<lambda>s. Q' s \<and> R' s)" for Q Q' R'
            in stronger_corres_guard_imp[rotated])
    apply assumption
   apply (rule conjI, assumption)
   apply (clarsimp simp: cte_wp_at_ctes_of)
   apply (drule cte_wp_at_is_reply_cap_toI)
   apply (erule(4) reply_cap_end_mdb_chain)
  apply (rule corres_assert_assume[rotated], simp)
  apply (simp add: getSlotCap_def)
  apply (rule corres_symb_exec_r[OF _ getCTE_sp getCTE_inv, rotated])
   apply (rule no_fail_pre, wp)
   apply (clarsimp simp: cte_wp_at_ctes_of)
  apply (rule corres_assert_assume[rotated])
   apply (clarsimp simp: cte_wp_at_ctes_of)
  apply (rule corres_guard_imp)
    apply (rule corres_split [OF _ threadget_fault_corres])
      apply (case_tac rv, simp_all add: fault_rel_optionation_def bind_assoc)[1]
       apply (rule corres_split [OF _ dit_corres])
         apply (rule corres_split [OF _ cap_delete_one_corres])
           apply (rule corres_split [OF _ sts_corres])
              apply (rule possibleSwitchTo_corres)
             apply simp
            apply (wp set_thread_state_runnable_valid_sched set_thread_state_runnable_weak_valid_sched_action sts_st_tcb_at' sts_st_tcb' sts_valid_queues sts_valid_objs' delete_one_tcbDomain_obj_at'
                   | simp add: valid_tcb_state'_def)+
        apply (strengthen cte_wp_at_reply_cap_can_fast_finalise)
        apply (wp hoare_vcg_conj_lift)
         apply (rule hoare_strengthen_post [OF do_ipc_transfer_non_null_cte_wp_at])
          prefer 2
          apply (erule cte_wp_at_weakenE)
          apply (fastforce)
         apply (clarsimp simp:is_cap_simps)
        apply (wp weak_valid_sched_action_lift)+
       apply (rule_tac Q="\<lambda>_. valid_queues' and valid_objs' and cur_tcb' and tcb_at' receiver and (\<lambda>s. sch_act_wf (ksSchedulerAction s) s)" in hoare_post_imp, simp add: sch_act_wf_weak)
       apply (wp tcb_in_cur_domain'_lift)
      defer
      apply (simp)
      apply (wp)+
    apply (clarsimp)
    apply (rule conjI, erule invs_valid_objs)
    apply (rule conjI, clarsimp)+
    apply (rule conjI)
     apply (erule cte_wp_at_weakenE)
     apply (clarsimp)
     apply (rule conjI, rule refl)
     apply (fastforce)
    apply (clarsimp simp: invs_def valid_sched_def valid_sched_action_def)
   apply (simp)
   apply (auto simp: invs'_def valid_state'_def)[1]

  apply (rule corres_guard_imp)
    apply (rule corres_split [OF _ cap_delete_one_corres])
      apply (rule corres_split_mapr [OF _ get_mi_corres])
        apply (rule corres_split_eqr [OF _ lipcb_corres'])
          apply (rule corres_split_eqr [OF _ get_mrs_corres])
            apply (simp(no_asm) del: dc_simp)
            apply (rule corres_split_eqr [OF _ handle_fault_reply_corres])
               apply (rule corres_split [OF _ threadset_corresT])
                     apply (rule_tac Q="valid_sched and cur_tcb and tcb_at receiver"
                                 and Q'="tcb_at' receiver and cur_tcb'
                                           and (\<lambda>s. weak_sch_act_wf (ksSchedulerAction s) s)
                                           and Invariants_H.valid_queues and valid_queues' and valid_objs'"
                                   in corres_guard_imp)
                       apply (case_tac rvb, simp_all)[1]
                        apply (rule corres_guard_imp)
                          apply (rule corres_split [OF _ sts_corres])
                      apply (fold dc_def, rule possibleSwitchTo_corres)
                               apply simp
                              apply (wp static_imp_wp static_imp_conj_wp set_thread_state_runnable_weak_valid_sched_action sts_st_tcb_at'
                                        sts_st_tcb' sts_valid_queues | simp | force simp: valid_sched_def valid_sched_action_def valid_tcb_state'_def)+
                       apply (rule corres_guard_imp)
                      apply (rule sts_corres)
                      apply (simp_all)[20]
                   apply (clarsimp simp add: tcb_relation_def fault_rel_optionation_def
                                             tcb_cap_cases_def tcb_cte_cases_def exst_same_def)+
                  apply (wp threadSet_cur weak_sch_act_wf_lift_linear threadSet_pred_tcb_no_state
                            thread_set_not_state_valid_sched threadSet_valid_queues threadSet_valid_queues'
                            threadSet_tcbDomain_triv threadSet_valid_objs'
                       | simp add: valid_tcb_state'_def)+
               apply (wp threadSet_cur weak_sch_act_wf_lift_linear threadSet_pred_tcb_no_state
                         thread_set_not_state_valid_sched threadSet_valid_queues threadSet_valid_queues'
                    | simp add: runnable_def inQ_def valid_tcb'_def)+
     apply (rule_tac Q="\<lambda>_. valid_sched and cur_tcb and tcb_at sender and tcb_at receiver and valid_objs and pspace_aligned"
                     in hoare_strengthen_post [rotated], clarsimp)
     apply (wp)
     apply (rule hoare_chain [OF cap_delete_one_invs])
      apply (assumption)
     apply (rule conjI, clarsimp)
     apply (clarsimp simp add: invs_def valid_state_def)
    apply (rule_tac Q="\<lambda>_. tcb_at' sender and tcb_at' receiver and invs'"
                    in hoare_strengthen_post [rotated])
     apply (solves\<open>auto simp: invs'_def valid_state'_def\<close>)
    apply wp
   apply clarsimp
   apply (rule conjI)
    apply (erule cte_wp_at_weakenE)
    apply (clarsimp simp add: can_fast_finalise_def)
   apply (erule(1) emptyable_cte_wp_atD)
   apply (rule allI, rule impI)
   apply (clarsimp simp add: is_master_reply_cap_def)
  apply (clarsimp)
  done
  *)

(* FIXME RT: move/eliminate *)
lemma valid_pspace'_splits[elim!]:
  "valid_pspace' s \<Longrightarrow> pspace_aligned' s"
  "valid_pspace' s \<Longrightarrow> pspace_distinct' s"
  "valid_pspace' s \<Longrightarrow> no_0_obj' s"
  by (simp add: valid_pspace'_def)+

lemma sts_valid_pspace_hangers:
  "\<lbrace>valid_pspace' and tcb_at' t and
   valid_tcb_state' st\<rbrace> setThreadState st t \<lbrace>\<lambda>rv. valid_objs'\<rbrace>"
  "\<lbrace>valid_pspace' and tcb_at' t and
   valid_tcb_state' st\<rbrace> setThreadState st t \<lbrace>\<lambda>rv. pspace_distinct'\<rbrace>"
  "\<lbrace>valid_pspace' and tcb_at' t and
   valid_tcb_state' st\<rbrace> setThreadState st t \<lbrace>\<lambda>rv. pspace_aligned'\<rbrace>"
  "\<lbrace>valid_pspace' and tcb_at' t and
   valid_tcb_state' st\<rbrace> setThreadState st t \<lbrace>\<lambda>rv. valid_mdb'\<rbrace>"
  "\<lbrace>valid_pspace' and tcb_at' t and
   valid_tcb_state' st\<rbrace> setThreadState st t \<lbrace>\<lambda>rv. no_0_obj'\<rbrace>"
  by (safe intro!: hoare_strengthen_post [OF sts'_valid_pspace'_inv])

declare no_fail_getSlotCap [wp]

lemma cteInsert_sch_act_wf[wp]:
  "\<lbrace>\<lambda>s. sch_act_wf (ksSchedulerAction s) s\<rbrace>
     cteInsert newCap srcSlot destSlot
   \<lbrace>\<lambda>_ s. sch_act_wf (ksSchedulerAction s) s\<rbrace>"
by (wp sch_act_wf_lift tcb_in_cur_domain'_lift)

lemmas transferCapsToSlots_pred_tcb_at' =
    transferCapsToSlots_pres1 [OF cteInsert_pred_tcb_at']

crunches doIPCTransfer, possibleSwitchTo
  for pred_tcb_at'[wp]: "pred_tcb_at' proj P t"
  (wp: mapM_wp' crunch_wps simp: zipWithM_x_mapM)


(* FIXME move *)
lemma tcb_in_cur_domain'_ksSchedulerAction_update[simp]:
  "tcb_in_cur_domain' t (ksSchedulerAction_update f s) = tcb_in_cur_domain' t s"
by (simp add: tcb_in_cur_domain'_def)

(* FIXME move *)
lemma ct_idle_or_in_cur_domain'_ksSchedulerAction_update[simp]:
  "b\<noteq> ResumeCurrentThread \<Longrightarrow>
   ct_idle_or_in_cur_domain' (s\<lparr>ksSchedulerAction := b\<rparr>)"
  apply (clarsimp simp add: ct_idle_or_in_cur_domain'_def)
  done

lemma setSchedulerAction_ct_in_domain:
 "\<lbrace>\<lambda>s. ct_idle_or_in_cur_domain' s
   \<and>  p \<noteq> ResumeCurrentThread \<rbrace> setSchedulerAction p
  \<lbrace>\<lambda>_. ct_idle_or_in_cur_domain'\<rbrace>"
  by (simp add:setSchedulerAction_def | wp)+

crunches doIPCTransfer, possibleSwitchTo
  for ct_idle_or_in_cur_domain'[wp]: ct_idle_or_in_cur_domain'
  and ksCurDomain[wp]: "\<lambda>s. P (ksCurDomain s)"
  and ksDomSchedule[wp]: "\<lambda>s. P (ksDomSchedule s)"
  (wp: crunch_wps setSchedulerAction_ct_in_domain simp: zipWithM_x_mapM)

crunch tcbDomain_obj_at'[wp]: doIPCTransfer "obj_at' (\<lambda>tcb. P (tcbDomain tcb)) t"
  (wp: crunch_wps constOnFailure_wp simp: crunch_simps)

crunches possibleSwitchTo
  for tcb_at'[wp]: "tcb_at' t"
  and valid_pspace'[wp]: valid_pspace'
  (wp: crunch_wps)

lemma send_ipc_corres:
(* call is only true if called in handleSyscall SysCall, which
   is always blocking. *)
  assumes "call \<longrightarrow> bl"
  shows
  "corres dc (einvs and st_tcb_at active t and ep_at ep and ex_nonz_cap_to t)
             (invs' and  sch_act_not t and tcb_at' t and ep_at' ep)
             (send_ipc bl call bg cg cgr cd t ep) (sendIPC bl call bg cg cgr cd t ep)"
proof -
  show ?thesis
  apply (insert assms)
  apply (unfold send_ipc_def sendIPC_def Let_def)
  apply (case_tac bl)
   apply clarsimp
   apply (rule corres_guard_imp)
     apply (rule corres_split [OF _ get_ep_corres,
              where
              R="\<lambda>rv. einvs and st_tcb_at active t and ep_at ep and
                      valid_ep rv and obj_at (\<lambda>ob. ob = Endpoint rv) ep
                      and ex_nonz_cap_to t"
              and
              R'="\<lambda>rv'. invs' and tcb_at' t and sch_act_not t
                              and ep_at' ep and valid_ep' rv'"])
       apply (case_tac rv)
         apply (simp add: ep_relation_def)
         apply (rule corres_guard_imp)
           apply (rule corres_split [OF _ sts_corres])
              apply (rule set_ep_corres)
              apply (simp add: ep_relation_def)
             apply (simp add: fault_rel_optionation_def)
            apply wp+
          apply (clarsimp simp: st_tcb_at_tcb_at valid_tcb_state_def)
  sorry (*
         apply clarsimp
         \<comment> \<open>concludes IdleEP if bl branch\<close>
        apply (simp add: ep_relation_def)
        apply (rule corres_guard_imp)
          apply (rule corres_split [OF _ sts_corres])
             apply (rule set_ep_corres)
             apply (simp add: ep_relation_def)
            apply (simp add: fault_rel_optionation_def)
           apply wp+
         apply (clarsimp simp: st_tcb_at_tcb_at valid_tcb_state_def)
        apply clarsimp
        \<comment> \<open>concludes SendEP if bl branch\<close>
       apply (simp add: ep_relation_def)
       apply (rename_tac list)
       apply (rule_tac F="list \<noteq> []" in corres_req)
        apply (simp add: valid_ep_def)
       apply (case_tac list)
        apply simp
       apply (clarsimp split del: if_split)
       apply (rule corres_guard_imp)
         apply (rule corres_split [OF _ set_ep_corres])
            apply (simp add: isReceive_def split del:if_split)
            apply (rule corres_split [OF _ gts_corres])
              apply (rule_tac
                     F="\<exists>data. recv_state = Structures_A.BlockedOnReceive ep data"
                     in corres_gen_asm)
              apply (clarsimp simp: case_bool_If  case_option_If if3_fold
                          simp del: dc_simp split del: if_split cong: if_cong)
              apply (rule corres_split [OF _ dit_corres])
                apply (rule corres_split [OF _ sts_corres])
                   apply (rule corres_split [OF _ possibleSwitchTo_corres])
                       apply (fold when_def)[1]

                       apply (rule_tac P="call" and P'="call"
                                in corres_symmetric_bool_cases, blast)
                        apply (simp add: when_def dc_def[symmetric] split del: if_split)
                        apply (rule corres_if2, simp)
                         apply (rule setup_caller_corres)
                        apply (rule sts_corres, simp)
                       apply (rule corres_trivial)
                       apply (simp add: when_def dc_def[symmetric] split del: if_split)
                      apply (simp split del: if_split add: if_apply_def2)
                      apply (wp hoare_drop_imps)[1]
                     apply (simp split del: if_split add: if_apply_def2)
                     apply (wp hoare_drop_imps)[1]
                    apply (wp | simp)+
                 apply (wp sts_cur_tcb set_thread_state_runnable_weak_valid_sched_action sts_st_tcb_at_cases)
                apply (wp setThreadState_valid_queues' sts_valid_queues sts_weak_sch_act_wf
                          sts_cur_tcb' setThreadState_tcb' sts_st_tcb_at'_cases)[1]
               apply (simp add: valid_tcb_state_def pred_conj_def)
               apply (strengthen reply_cap_doesnt_exist_strg disjI2_strg)
               apply ((wp hoare_drop_imps do_ipc_transfer_tcb_caps weak_valid_sched_action_lift
                    | clarsimp simp: is_cap_simps)+)[1]
              apply (simp add: pred_conj_def)
              apply (strengthen sch_act_wf_weak)
              apply (simp add: valid_tcb_state'_def)
              apply (wp weak_sch_act_wf_lift_linear tcb_in_cur_domain'_lift hoare_drop_imps)[1]
             apply (wp gts_st_tcb_at)+
           apply (simp add: ep_relation_def split: list.split)
          apply (simp add: pred_conj_def cong: conj_cong)
          apply (wp hoare_post_taut)
         apply (simp)
         apply (wp weak_sch_act_wf_lift_linear set_ep_valid_objs' setEndpoint_valid_mdb')+
        apply (clarsimp simp add: invs_def valid_state_def valid_pspace_def ep_redux_simps
                        ep_redux_simps' st_tcb_at_tcb_at valid_ep_def
                        cong: list.case_cong)
        apply (drule(1) sym_refs_obj_atD[where P="\<lambda>ob. ob = e" for e])
        apply (clarsimp simp: st_tcb_at_refs_of_rev st_tcb_at_reply_cap_valid
                              st_tcb_def2 valid_sched_def valid_sched_action_def)
        apply (force simp: st_tcb_def2 dest!: st_tcb_at_caller_cap_null[simplified,rotated])
       subgoal by (auto simp: valid_ep'_def invs'_def valid_state'_def split: list.split)
      apply wp+
    apply (clarsimp simp: ep_at_def2)+
  apply (rule corres_guard_imp)
    apply (rule corres_split [OF _ get_ep_corres,
             where
             R="\<lambda>rv. einvs and st_tcb_at active t and ep_at ep and
                     valid_ep rv and obj_at (\<lambda>k. k = Endpoint rv) ep"
             and
             R'="\<lambda>rv'. invs' and tcb_at' t and sch_act_not t
                             and ep_at' ep and valid_ep' rv'"])
      apply (rename_tac rv rv')
      apply (case_tac rv)
        apply (simp add: ep_relation_def)
        \<comment> \<open>concludes IdleEP branch if not bl and no ft\<close>
       apply (simp add: ep_relation_def)
       \<comment> \<open>concludes SendEP branch if not bl and no ft\<close>
      apply (simp add: ep_relation_def)
      apply (rename_tac list)
      apply (rule_tac F="list \<noteq> []" in corres_req)
       apply (simp add: valid_ep_def)
      apply (case_tac list)
       apply simp
      apply (rule_tac F="a \<noteq> t" in corres_req)
       apply (clarsimp simp: invs_def valid_state_def
                             valid_pspace_def)
       apply (drule(1) sym_refs_obj_atD[where P="\<lambda>ob. ob = e" for e])
       apply (clarsimp simp: st_tcb_at_def obj_at_def tcb_bound_refs_def2)
       apply fastforce
      apply (clarsimp split del: if_split)
      apply (rule corres_guard_imp)
        apply (rule corres_split [OF _ set_ep_corres])
           apply (rule corres_split [OF _ gts_corres])
             apply (rule_tac
                F="\<exists>data. recv_state = Structures_A.BlockedOnReceive ep data"
                    in corres_gen_asm)
             apply (clarsimp simp: isReceive_def case_bool_If
                        split del: if_split cong: if_cong)
             apply (rule corres_split [OF _ dit_corres])
               apply (rule corres_split [OF _ sts_corres])
                   apply (rule possibleSwitchTo_corres)
                  apply (simp add: if_apply_def2)
                  apply (wp hoare_drop_imps)
                  apply (simp add: if_apply_def2)
                apply ((wp sts_cur_tcb set_thread_state_runnable_weak_valid_sched_action sts_st_tcb_at_cases |
                           simp add: if_apply_def2 split del: if_split)+)[1]
               apply (wp setThreadState_valid_queues' sts_valid_queues sts_weak_sch_act_wf
                         sts_cur_tcb' setThreadState_tcb' sts_st_tcb_at'_cases)
              apply (simp add: valid_tcb_state_def pred_conj_def)
              apply ((wp hoare_drop_imps do_ipc_transfer_tcb_caps  weak_valid_sched_action_lift
                     | clarsimp simp:is_cap_simps)+)[1]
             apply (simp add: valid_tcb_state'_def pred_conj_def)
             apply (strengthen sch_act_wf_weak)
             apply (wp weak_sch_act_wf_lift_linear hoare_drop_imps)
            apply (wp gts_st_tcb_at)+
          apply (simp add: ep_relation_def split: list.split)
         apply (simp add: pred_conj_def cong: conj_cong)
         apply (wp hoare_post_taut)
        apply simp
        apply (wp weak_sch_act_wf_lift_linear set_ep_valid_objs' setEndpoint_valid_mdb')
       apply (clarsimp simp add: invs_def valid_state_def
                                 valid_pspace_def ep_redux_simps ep_redux_simps'
                                 st_tcb_at_tcb_at
                           cong: list.case_cong)
       apply (clarsimp simp: valid_ep_def)
       apply (drule(1) sym_refs_obj_atD[where P="\<lambda>ob. ob = e" for e])
       apply (clarsimp simp: st_tcb_at_refs_of_rev st_tcb_at_reply_cap_valid
                             st_tcb_at_caller_cap_null)
       apply (fastforce simp: st_tcb_def2 valid_sched_def valid_sched_action_def)
      subgoal by (auto simp: valid_ep'_def
                      split: list.split;
                  clarsimp simp: invs'_def valid_state'_def)
     apply wp+
   apply (clarsimp simp: ep_at_def2)+
  done *)
qed

lemmas setMessageInfo_typ_ats[wp] = typ_at_lifts [OF setMessageInfo_typ_at']

(* Annotation added by Simon Winwood (Thu Jul  1 20:54:41 2010) using taint-mode *)
declare tl_drop_1[simp]

crunches cancel_ipc
  for cur[wp]: "cur_tcb"
  (wp: select_wp crunch_wps simp: crunch_simps)

lemma valid_sched_weak_strg:
  "valid_sched s \<longrightarrow> weak_valid_sched_action s"
  by (simp add: valid_sched_def valid_sched_action_def)

lemma send_signal_corres:
  "corres dc (einvs and ntfn_at ep) (invs' and ntfn_at' ep)
             (send_signal ep bg) (sendSignal ep bg)"
  apply (simp add: send_signal_def sendSignal_def Let_def)
  apply (rule corres_guard_imp)
    apply (rule corres_split [OF _ get_ntfn_corres,
                where
                R  = "\<lambda>rv. einvs and ntfn_at ep and valid_ntfn rv and
                           ko_at (Structures_A.Notification rv) ep" and
                R' = "\<lambda>rv'. invs' and ntfn_at' ep and
                            valid_ntfn' rv' and ko_at' rv' ep"])
      defer
      apply (wp get_simple_ko_ko_at get_ntfn_ko')+
    apply (simp add: invs_valid_objs)+
  apply (case_tac "ntfn_obj ntfn")
    \<comment> \<open>IdleNtfn\<close>
    apply (clarsimp simp add: ntfn_relation_def)
    apply (case_tac "ntfnBoundTCB nTFN")
     apply clarsimp
     apply (rule corres_guard_imp[OF set_ntfn_corres])
       apply (clarsimp simp add: ntfn_relation_def)+
    apply (rule corres_guard_imp)
      apply (rule corres_split[OF _ gts_corres])
        apply (rule corres_if)
          apply (fastforce simp: receive_blocked_def receiveBlocked_def
                                 thread_state_relation_def
                          split: Structures_A.thread_state.splits
                                 Structures_H.thread_state.splits)
         apply (rule corres_split[OF _ cancel_ipc_corres])
           apply (rule corres_split[OF _ sts_corres])
              apply (simp add: badgeRegister_def badge_register_def)
              apply (rule corres_split[OF _ user_setreg_corres])
  sorry (*
                apply (rule possibleSwitchTo_corres)
               apply wp
             apply (clarsimp simp: thread_state_relation_def)
            apply (wp set_thread_state_runnable_weak_valid_sched_action sts_st_tcb_at'
                      sts_valid_queues sts_st_tcb' hoare_disjI2
                      cancel_ipc_cte_wp_at_not_reply_state
                 | strengthen invs_vobjs_strgs invs_psp_aligned_strg valid_sched_weak_strg
                 | simp add: valid_tcb_state_def)+
         apply (rule_tac Q="\<lambda>rv. invs' and tcb_at' a" in hoare_strengthen_post)
          apply wp
         apply (clarsimp simp: invs'_def valid_state'_def sch_act_wf_weak
                               valid_tcb_state'_def)
        apply (rule set_ntfn_corres)
        apply (clarsimp simp add: ntfn_relation_def)
       apply (wp gts_wp gts_wp' | clarsimp)+
     apply (auto simp: valid_ntfn_def receive_blocked_def valid_sched_def invs_cur
                 elim: pred_tcb_weakenE
                intro: st_tcb_at_reply_cap_valid
                split: Structures_A.thread_state.splits)[1]
    apply (clarsimp simp: valid_ntfn'_def invs'_def valid_state'_def valid_pspace'_def sch_act_wf_weak)
   \<comment> \<open>WaitingNtfn\<close>
   apply (clarsimp simp add: ntfn_relation_def Let_def)
   apply (simp add: update_waiting_ntfn_def)
   apply (rename_tac list)
   apply (case_tac "tl list = []")
    \<comment> \<open>tl list = []\<close>
    apply (rule corres_guard_imp)
      apply (rule_tac F="list \<noteq> []" in corres_gen_asm)
      apply (simp add: list_case_helper split del: if_split)
      apply (rule corres_split [OF _ set_ntfn_corres])
         apply (rule corres_split [OF _ sts_corres])
            apply (simp add: badgeRegister_def badge_register_def)
            apply (rule corres_split [OF _ user_setreg_corres])
              apply (rule possibleSwitchTo_corres)
             apply ((wp | simp)+)[1]
            apply (rule_tac Q="\<lambda>_. Invariants_H.valid_queues and valid_queues' and
                                   (\<lambda>s. sch_act_wf (ksSchedulerAction s) s) and
                                   cur_tcb' and
                                   st_tcb_at' runnable' (hd list) and valid_objs'"
                     in hoare_post_imp, clarsimp simp: pred_tcb_at' elim!: sch_act_wf_weak)
            apply (wp | simp)+
          apply (wp sts_st_tcb_at' set_thread_state_runnable_weak_valid_sched_action
               | simp)+
         apply (wp sts_st_tcb_at'_cases sts_valid_queues setThreadState_valid_queues'
                   setThreadState_st_tcb
              | simp)+
        apply (simp add: ntfn_relation_def)
       apply (wp set_simple_ko_valid_objs set_ntfn_aligned' set_ntfn_valid_objs'
                 hoare_vcg_disj_lift weak_sch_act_wf_lift_linear
            | simp add: valid_tcb_state_def valid_tcb_state'_def)+
     apply (clarsimp simp: invs_def valid_state_def valid_ntfn_def
                           valid_pspace_def ntfn_queued_st_tcb_at valid_sched_def
                           valid_sched_action_def)
    apply (auto simp: valid_ntfn'_def )[1]
    apply (clarsimp simp: invs'_def valid_state'_def)

   \<comment> \<open>tl list \<noteq> []\<close>
   apply (rule corres_guard_imp)
     apply (rule_tac F="list \<noteq> []" in corres_gen_asm)
     apply (simp add: list_case_helper)
     apply (rule corres_split [OF _ set_ntfn_corres])
        apply (rule corres_split [OF _ sts_corres])
           apply (simp add: badgeRegister_def badge_register_def)
           apply (rule corres_split [OF _ user_setreg_corres])
             apply (rule possibleSwitchTo_corres)
            apply (wp cur_tcb_lift | simp)+
         apply (wp sts_st_tcb_at' set_thread_state_runnable_weak_valid_sched_action
              | simp)+
        apply (wp sts_st_tcb_at'_cases sts_valid_queues setThreadState_valid_queues'
                  setThreadState_st_tcb
             | simp)+
       apply (simp add: ntfn_relation_def split:list.splits)
      apply (wp set_ntfn_aligned' set_simple_ko_valid_objs set_ntfn_valid_objs'
                hoare_vcg_disj_lift weak_sch_act_wf_lift_linear
           | simp add: valid_tcb_state_def valid_tcb_state'_def)+
    apply (clarsimp simp: invs_def valid_state_def valid_ntfn_def
                          valid_pspace_def neq_Nil_conv
                          ntfn_queued_st_tcb_at valid_sched_def valid_sched_action_def
                  split: option.splits)
   apply (auto simp: valid_ntfn'_def neq_Nil_conv invs'_def valid_state'_def
                     weak_sch_act_wf_def
              split: option.splits)[1]
  \<comment> \<open>ActiveNtfn\<close>
  apply (clarsimp simp add: ntfn_relation_def)
  apply (rule corres_guard_imp)
    apply (rule set_ntfn_corres)
    apply (simp add: ntfn_relation_def combine_ntfn_badges_def
                     combine_ntfn_msgs_def)
   apply (simp add: invs_def valid_state_def valid_ntfn_def)
  apply (simp add: invs'_def valid_state'_def valid_ntfn'_def)
  done *)

lemma valid_Running'[simp]:
  "valid_tcb_state' Running = \<top>"
  by (rule ext, simp add: valid_tcb_state'_def)

lemma possibleSwitchTo_sch_act[wp]:
  "\<lbrace>\<lambda>s. sch_act_wf (ksSchedulerAction s) s \<and> st_tcb_at' runnable' t s\<rbrace>
     possibleSwitchTo t
   \<lbrace>\<lambda>rv s. sch_act_wf (ksSchedulerAction s) s\<rbrace>"
  apply (simp add: possibleSwitchTo_def curDomain_def bitmap_fun_defs)
  apply (wp static_imp_wp threadSet_sch_act setQueue_sch_act threadGet_wp
       | simp add: unless_def | wpc)+
  apply (auto simp: obj_at'_def projectKOs tcb_in_cur_domain'_def)
  sorry

lemma possibleSwitchTo_ksQ':
  "\<lbrace>(\<lambda>s. t' \<notin> set (ksReadyQueues s p) \<and> sch_act_not t' s) and K(t' \<noteq> t)\<rbrace>
     possibleSwitchTo t
   \<lbrace>\<lambda>_ s. t' \<notin> set (ksReadyQueues s p)\<rbrace>"
  apply (simp add: possibleSwitchTo_def curDomain_def bitmap_fun_defs inReleaseQueue_def)
  apply (wp static_imp_wp rescheduleRequired_ksQ' tcbSchedEnqueue_ksQ threadGet_wp
         | wpc
         | simp split del: if_split)+
  apply (auto simp: obj_at'_def)
  done

crunch st_refs_of'[wp]: possibleSwitchTo "\<lambda>s. P (state_refs_of' s)"
  (wp: crunch_wps)

crunch cap_to'[wp]: possibleSwitchTo "ex_nonz_cap_to' p"
  (wp: crunch_wps)
crunch objs'[wp]: possibleSwitchTo valid_objs'
  (wp: crunch_wps)
crunch ct[wp]: possibleSwitchTo cur_tcb'
  (wp: cur_tcb_lift crunch_wps)

lemma possibleSwitchTo_iflive[wp]:
  "\<lbrace>if_live_then_nonz_cap' and ex_nonz_cap_to' t
           and (\<lambda>s. sch_act_wf (ksSchedulerAction s) s)\<rbrace>
     possibleSwitchTo t
   \<lbrace>\<lambda>rv. if_live_then_nonz_cap'\<rbrace>"
  apply (simp add: possibleSwitchTo_def curDomain_def)
  apply (wp | wpc | simp)+
      apply (simp only: imp_conv_disj, wp hoare_vcg_all_lift hoare_vcg_disj_lift)
    apply (wp threadGet_wp)+
  apply (auto simp: obj_at'_def projectKOs)
  sorry

crunches possibleSwitchTo
  for ifunsafe[wp]: if_unsafe_then_cap'
  and idle'[wp]: valid_idle'
  and global_refs'[wp]: valid_global_refs'
  and arch_state'[wp]: valid_arch_state'
  and irq_handlers'[wp]: valid_irq_handlers'
  and irq_states'[wp]: valid_irq_states'
  and pde_mappigns'[wp]: valid_pde_mappings'
  (wp: crunch_wps simp: unless_def tcb_cte_cases_def)

lemma replyRemoveTCB_ct'[wp]:
  "replyRemoveTCB t \<lbrace> \<lambda>s. P (ksCurThread s) \<rbrace>"
  unfolding replyRemoveTCB_def
  by (wpsimp wp: hoare_drop_imps gts_wp'|rule conjI)+

lemma sts_irqs_masked'[wp]:
  "setThreadState st t \<lbrace> irqs_masked' \<rbrace>"
  sorry

crunches replyUnlink, cleanReply
  for irqs_masked'[wp]: "irqs_masked'"
  (wp: crunch_wps)

lemma replyRemoveTCB_irqs_masked'[wp]:
  "replyRemoveTCB t \<lbrace> irqs_masked' \<rbrace>"
  unfolding replyRemoveTCB_def
  by (wpsimp wp: hoare_drop_imps gts_wp'|rule conjI)+

crunches sendSignal
  for ct'[wp]: "\<lambda>s. P (ksCurThread s)"
  and it'[wp]: "\<lambda>s. P (ksIdleThread s)"
  and irqs_masked'[wp]: "irqs_masked'"
  (wp: crunch_wps whileM_inv simp: crunch_simps o_def)

lemma sts_running_valid_queues:
  "runnable' st \<Longrightarrow> \<lbrace> Invariants_H.valid_queues \<rbrace> setThreadState st t \<lbrace>\<lambda>_. Invariants_H.valid_queues \<rbrace>"
  by (wp sts_valid_queues, clarsimp)

lemma ct_in_state_activatable_imp_simple'[simp]:
  "ct_in_state' activatable' s \<Longrightarrow> ct_in_state' simple' s"
  apply (simp add: ct_in_state'_def)
  apply (erule pred_tcb'_weakenE)
  apply (case_tac st; simp)
  done

lemma setThreadState_nonqueued_state_update:
  "\<lbrace>\<lambda>s. invs' s \<and> st_tcb_at' simple' t s
               \<and> st \<in> {Inactive, Running, Restart, IdleThreadState}
               \<and> (st \<noteq> Inactive \<longrightarrow> ex_nonz_cap_to' t s)
               \<and> (t = ksIdleThread s \<longrightarrow> idle' st)

               \<and> (\<not> runnable' st \<longrightarrow> sch_act_simple s)
               \<and> (\<not> runnable' st \<longrightarrow> (\<forall>p. t \<notin> set (ksReadyQueues s p)))\<rbrace>
  setThreadState st t \<lbrace>\<lambda>rv. invs'\<rbrace>"
  apply (simp add: invs'_def valid_state'_def valid_dom_schedule'_def)
  apply (rule hoare_pre, wp valid_irq_node_lift
                            sts_valid_queues
                            setThreadState_ct_not_inQ)
  apply (clarsimp simp: pred_tcb_at')
  apply (rule conjI, fastforce simp: valid_tcb_state'_def)
  sorry (*
  apply (drule simple_st_tcb_at_state_refs_ofD')
  apply (drule bound_tcb_at_state_refs_ofD')
  apply (rule conjI, fastforce)
  apply clarsimp
  apply (erule delta_sym_refs)
   apply (fastforce split: if_split_asm)
  apply (fastforce simp: symreftype_inverse' tcb_bound_refs'_def
                  split: if_split_asm)
  done *)

lemma cteDeleteOne_reply_cap_to'[wp]:
  "\<lbrace>ex_nonz_cap_to' p and
    cte_wp_at' (\<lambda>c. isReplyCap (cteCap c)) slot\<rbrace>
   cteDeleteOne slot
   \<lbrace>\<lambda>rv. ex_nonz_cap_to' p\<rbrace>"
  apply (simp add: cteDeleteOne_def ex_nonz_cap_to'_def unless_def)
  apply (rule hoare_seq_ext [OF _ getCTE_sp])
  apply (rule hoare_assume_pre)
  apply (subgoal_tac "isReplyCap (cteCap cte)")
   apply (wp hoare_vcg_ex_lift emptySlot_cte_wp_cap_other isFinalCapability_inv
        | clarsimp simp: finaliseCap_def isCap_simps | simp
        | wp (once) hoare_drop_imps)+
   apply (fastforce simp: cte_wp_at_ctes_of)
  apply (clarsimp simp: cte_wp_at_ctes_of isCap_simps)
  done

crunches possibleSwitchTo, asUser, doIPCTransfer
  for vms'[wp]: "valid_machine_state'"
  (wp: crunch_wps simp: zipWithM_x_mapM_x)

crunches cancelSignal
  for nonz_cap_to'[wp]: "ex_nonz_cap_to' p"
  (wp: crunch_wps simp: crunch_simps)

lemma cancelIPC_nonz_cap_to'[wp]:
  "cancelIPC t \<lbrace>ex_nonz_cap_to' p\<rbrace>"
  apply (simp add: cancelIPC_def Let_def
                   capHasProperty_def)
  sorry (*
  apply (wp threadSet_cap_to'
       | wpc
       | simp
       | clarsimp elim!: cte_wp_at_weakenE'
       | rule hoare_post_imp[where Q="\<lambda>rv. ex_nonz_cap_to' p"])+
  done *)


crunches activateIdleThread, isFinalCapability
  for nosch[wp]:  "\<lambda>s. P (ksSchedulerAction s)"
  (ignore: setNextPC simp: Let_def)

crunches asUser, setMRs, doIPCTransfer, possibleSwitchTo
  for pspace_domain_valid[wp]: "pspace_domain_valid"
  (wp: crunch_wps simp: zipWithM_x_mapM_x)

crunches doIPCTransfer, possibleSwitchTo
  for ksDomScheduleIdx[wp]: "\<lambda>s. P (ksDomScheduleIdx s)"
  (wp: crunch_wps simp: zipWithM_x_mapM)

lemma setThreadState_not_rct[wp]:
  "\<lbrace>\<lambda>s. ksSchedulerAction s \<noteq> ResumeCurrentThread \<rbrace>
   setThreadState st t
   \<lbrace>\<lambda>_ s. ksSchedulerAction s \<noteq> ResumeCurrentThread \<rbrace>"
  apply (simp add: setThreadState_def)
  sorry (*
  apply (wp)
       apply (rule hoare_post_imp [OF _ rescheduleRequired_notresume], simp)
      apply (simp)
      apply (wp)+
  apply simp
  done *)

lemma cancelAllIPC_not_rct[wp]:
  "\<lbrace>\<lambda>s. ksSchedulerAction s \<noteq> ResumeCurrentThread \<rbrace>
   cancelAllIPC epptr
   \<lbrace>\<lambda>_ s. ksSchedulerAction s \<noteq> ResumeCurrentThread \<rbrace>"
  apply (simp add: cancelAllIPC_def)
  sorry (*
  apply (wp | wpc)+
       apply (rule hoare_post_imp [OF _ rescheduleRequired_notresume], simp)
      apply simp
      apply (rule mapM_x_wp_inv)
      apply (wp)+
     apply (rule hoare_post_imp [OF _ rescheduleRequired_notresume], simp)
    apply simp
    apply (rule mapM_x_wp_inv)
    apply (wp)+
  apply (wp hoare_vcg_all_lift hoare_drop_imp)
    apply (simp_all)
  done *)

lemma cancelAllSignals_not_rct[wp]:
  "\<lbrace>\<lambda>s. ksSchedulerAction s \<noteq> ResumeCurrentThread \<rbrace>
   cancelAllSignals epptr
   \<lbrace>\<lambda>_ s. ksSchedulerAction s \<noteq> ResumeCurrentThread \<rbrace>"
  apply (simp add: cancelAllSignals_def)
  sorry (*
  apply (wp | wpc)+
     apply (rule hoare_post_imp [OF _ rescheduleRequired_notresume], simp)
    apply simp
    apply (rule mapM_x_wp_inv)
    apply (wp)+
  apply (wp hoare_vcg_all_lift hoare_drop_imp)
    apply (simp_all)
  done *)

crunches finaliseCapTrue_standin
  for not_rct[wp]: "\<lambda>s. ksSchedulerAction s \<noteq> ResumeCurrentThread"
  (simp: crunch_simps wp: crunch_wps)

lemma cancelIPC_ResumeCurrentThread_imp_notct[wp]:
  "\<lbrace>\<lambda>s. ksSchedulerAction s = ResumeCurrentThread \<longrightarrow> ksCurThread s \<noteq> t'\<rbrace>
   cancelIPC t
   \<lbrace>\<lambda>_ s. ksSchedulerAction s = ResumeCurrentThread \<longrightarrow> ksCurThread s \<noteq> t'\<rbrace>"
  (is "\<lbrace>?PRE t'\<rbrace> _ \<lbrace>_\<rbrace>")
proof -
  have aipc: "\<And>t t' ntfn.
    \<lbrace>\<lambda>s. ksSchedulerAction s = ResumeCurrentThread \<longrightarrow> ksCurThread s \<noteq> t'\<rbrace>
    cancelSignal t ntfn
    \<lbrace>\<lambda>_ s. ksSchedulerAction s = ResumeCurrentThread \<longrightarrow> ksCurThread s \<noteq> t'\<rbrace>"
    apply (simp add: cancelSignal_def)
    apply (wp)[1]
        apply (wp hoare_convert_imp)+
        apply (rule_tac P="\<lambda>s. ksSchedulerAction s \<noteq> ResumeCurrentThread"
                 in hoare_weaken_pre)
          apply (wpc)
           apply (wp | simp)+
       apply (wpc, wp+)
     apply (rule_tac Q="\<lambda>_. ?PRE t'" in hoare_post_imp, clarsimp)
     apply (wp)
    apply simp
    done
  have cdo: "\<And>t t' slot.
    \<lbrace>\<lambda>s. ksSchedulerAction s = ResumeCurrentThread \<longrightarrow> ksCurThread s \<noteq> t'\<rbrace>
    cteDeleteOne slot
    \<lbrace>\<lambda>_ s. ksSchedulerAction s = ResumeCurrentThread \<longrightarrow> ksCurThread s \<noteq> t'\<rbrace>"
    apply (simp add: cteDeleteOne_def unless_def split_def)
    apply (wp)
        apply (wp hoare_convert_imp)[1]
       apply (wp)
      apply (rule_tac Q="\<lambda>_. ?PRE t'" in hoare_post_imp, clarsimp)
      apply (wp hoare_convert_imp | simp)+
     sorry
  show ?thesis
  apply (simp add: cancelIPC_def Let_def)
  apply (wp, wpc)
          prefer 4 \<comment> \<open>state = Running\<close>
          apply wp
         prefer 7 \<comment> \<open>state = Restart\<close>
         apply wp
        apply (wp)+
           apply (wp hoare_convert_imp)[1]
          apply (wpc, wp+)
  sorry (*
        apply (rule_tac Q="\<lambda>_. ?PRE t'" in hoare_post_imp, clarsimp)
        apply (wp cdo)+
         apply (rule_tac Q="\<lambda>_. ?PRE t'" in hoare_post_imp, clarsimp)
         apply ((wp aipc hoare_convert_imp)+)[6]
    apply (wp)
       apply (wp hoare_convert_imp)[1]
      apply (wpc, wp+)
    apply (rule_tac Q="\<lambda>_. ?PRE t'" in hoare_post_imp, clarsimp)
    apply (wp)
   apply (rule_tac Q="\<lambda>_. ?PRE t'" in hoare_post_imp, clarsimp)
   apply (wp)
  apply simp
  done *)
qed

lemma sai_invs'[wp]:
  "\<lbrace>invs' and ex_nonz_cap_to' ntfnptr\<rbrace>
     sendSignal ntfnptr badge \<lbrace>\<lambda>y. invs'\<rbrace>"
  unfolding sendSignal_def
  including no_pre
  apply (rule hoare_seq_ext[OF _ get_ntfn_sp'])
  apply (case_tac "ntfnObj nTFN", simp_all)
    prefer 3
    apply (rename_tac list)
    apply (case_tac list,
           simp_all split del: if_split
                          add: setMessageInfo_def)[1]
    apply (rule hoare_pre)
     apply (wp hoare_convert_imp [OF asUser_nosch]
               hoare_convert_imp [OF setMRs_sch_act])+
     apply (clarsimp simp:conj_comms)
     apply (simp add: invs'_def valid_state'_def)
  sorry (*
     apply ((wp valid_irq_node_lift sts_valid_objs' setThreadState_ct_not_inQ
               sts_valid_queues [where st="Structures_H.thread_state.Running", simplified]
               set_ntfn_valid_objs' cur_tcb_lift sts_st_tcb'
               hoare_convert_imp [OF set_ntfn'.ksSchedulerAction]
           | simp split del: if_split)+)[3]

    apply (intro conjI[rotated];
      (solves \<open>clarsimp simp: invs'_def valid_state'_def valid_pspace'_def\<close>)?)
           apply clarsimp
           apply (clarsimp simp: invs'_def valid_state'_def split del: if_split)
           apply (drule(1) ct_not_in_ntfnQueue, simp+)
          apply clarsimp
          apply (frule ko_at_valid_objs', clarsimp)
           apply (simp add: projectKOs)
          apply (clarsimp simp: valid_obj'_def valid_ntfn'_def
                         split: list.splits)
         apply (clarsimp simp: invs'_def valid_state'_def)
         apply (clarsimp simp: st_tcb_at_refs_of_rev' valid_idle'_def pred_tcb_at'_def
                        dest!: sym_refs_ko_atD' sym_refs_st_tcb_atD' sym_refs_obj_atD'
                        split: list.splits)
        apply (clarsimp simp: invs'_def valid_state'_def valid_pspace'_def)
        apply (frule(1) ko_at_valid_objs')
         apply (simp add: projectKOs)
        apply (clarsimp simp: valid_obj'_def valid_ntfn'_def
                    split: list.splits option.splits)
       apply (clarsimp elim!: if_live_then_nonz_capE' simp:invs'_def valid_state'_def)
       apply (drule(1) sym_refs_ko_atD')
       apply (clarsimp elim!: ko_wp_at'_weakenE
                   intro!: refs_of_live')
      apply (clarsimp split del: if_split)+
      apply (frule ko_at_valid_objs', clarsimp)
       apply (simp add: projectKOs)
      apply (clarsimp simp: valid_obj'_def valid_ntfn'_def split del: if_split)
      apply (frule invs_sym')
      apply (drule(1) sym_refs_obj_atD')
      apply (clarsimp split del: if_split cong: if_cong
                         simp: st_tcb_at_refs_of_rev' ep_redux_simps' ntfn_bound_refs'_def)
      apply (frule st_tcb_at_state_refs_ofD')
      apply (erule delta_sym_refs)
       apply (fastforce simp: split: if_split_asm)
      apply (fastforce simp: tcb_bound_refs'_def set_eq_subset symreftype_inverse'
                      split: if_split_asm)
     apply (clarsimp simp:invs'_def)
     apply (frule ko_at_valid_objs')
       apply (clarsimp simp: valid_pspace'_def valid_state'_def)
      apply (simp add: projectKOs)
     apply (clarsimp simp: valid_obj'_def valid_ntfn'_def split del: if_split)
    apply (clarsimp simp:invs'_def valid_state'_def valid_pspace'_def)
    apply (frule(1) ko_at_valid_objs')
     apply (simp add: projectKOs)
    apply (clarsimp simp: valid_obj'_def valid_ntfn'_def
                  split: list.splits option.splits)
   apply (case_tac "ntfnBoundTCB nTFN", simp_all)
    apply (wp set_ntfn_minor_invs')
    apply (fastforce simp: valid_ntfn'_def invs'_def valid_state'_def
                    elim!: obj_at'_weakenE
                    dest!: global'_no_ex_cap)
   apply (wp add: hoare_convert_imp [OF asUser_nosch]
             hoare_convert_imp [OF setMRs_sch_act]
             setThreadState_nonqueued_state_update sts_st_tcb'
             del: cancelIPC_simple)
     apply (clarsimp | wp cancelIPC_ct')+
    apply (wp set_ntfn_minor_invs' gts_wp' | clarsimp)+
   apply (frule pred_tcb_at')
   by (wp set_ntfn_minor_invs'
        | rule conjI
        | clarsimp elim!: st_tcb_ex_cap''
        | fastforce simp: receiveBlocked_def projectKOs pred_tcb_at'_def obj_at'_def
                   dest!: invs_rct_ct_activatable'
                   split: thread_state.splits
        | fastforce simp: invs'_def valid_state'_def receiveBlocked_def projectKOs
                          valid_obj'_def valid_ntfn'_def
                   split: thread_state.splits
                   dest!: global'_no_ex_cap st_tcb_ex_cap'' ko_at_valid_objs')+
  *)

lemma rfk_corres:
  "corres dc (tcb_at t and invs) (tcb_at' t and invs')
             (reply_from_kernel t r) (replyFromKernel t r)"
  apply (case_tac r)
  apply (clarsimp simp: replyFromKernel_def reply_from_kernel_def
                        badge_register_def badgeRegister_def)
  apply (rule corres_guard_imp)
    apply (rule corres_split_eqr [OF _ lipcb_corres])
      apply (rule corres_split [OF _ user_setreg_corres])
        apply (rule corres_split_eqr [OF _ set_mrs_corres])
           apply (rule set_mi_corres)
           apply (wp hoare_case_option_wp hoare_valid_ipc_buffer_ptr_typ_at'
                  | clarsimp)+
  done

lemma rfk_invs':
  "\<lbrace>invs' and tcb_at' t\<rbrace> replyFromKernel t r \<lbrace>\<lambda>rv. invs'\<rbrace>"
  apply (simp add: replyFromKernel_def)
  apply (cases r)
  apply wpsimp
  done

crunch nosch[wp]: replyFromKernel "\<lambda>s. P (ksSchedulerAction s)"

lemma complete_signal_corres:
  "corres dc (ntfn_at ntfnptr and tcb_at tcb and pspace_aligned and valid_objs
             \<comment> \<open>and obj_at (\<lambda>ko. ko = Notification ntfn \<and> Ipc_A.isActive ntfn) ntfnptr*\<close> )
             (ntfn_at' ntfnptr and tcb_at' tcb and valid_pspace' and obj_at' isActive ntfnptr)
             (complete_signal ntfnptr tcb) (completeSignal ntfnptr tcb)"
  apply (simp add: complete_signal_def completeSignal_def)
  apply (rule corres_guard_imp)
    apply (rule_tac R'="\<lambda>ntfn. ntfn_at' ntfnptr and tcb_at' tcb and valid_pspace'
                         and valid_ntfn' ntfn and (\<lambda>_. isActive ntfn)"
                                in corres_split [OF _ get_ntfn_corres])
      apply (rule corres_gen_asm2)
      apply (case_tac "ntfn_obj rv")
        apply (clarsimp simp: ntfn_relation_def isActive_def
                       split: ntfn.splits Structures_H.notification.splits)+
      apply (rule corres_guard2_imp)
       apply (simp add: badgeRegister_def badge_register_def)
       apply (rule corres_split[OF set_ntfn_corres user_setreg_corres])
         apply (clarsimp simp: ntfn_relation_def)
        apply (wp set_simple_ko_valid_objs get_simple_ko_wp getNotification_wp | clarsimp simp: valid_ntfn'_def)+
  apply (clarsimp simp: valid_pspace'_def)
  apply (rename_tac ntfn)
  apply (frule_tac P="(\<lambda>k. k = ntfn)" in obj_at_valid_objs', assumption)
  apply (clarsimp simp: projectKOs valid_obj'_def valid_ntfn'_def obj_at'_def)
  done


lemma do_nbrecv_failed_transfer_corres:
  "corres dc (tcb_at thread)
            (tcb_at' thread)
            (do_nbrecv_failed_transfer thread)
            (doNBRecvFailedTransfer thread)"
  unfolding do_nbrecv_failed_transfer_def doNBRecvFailedTransfer_def
  by (simp add: badgeRegister_def badge_register_def, rule user_setreg_corres)

lemma receive_ipc_corres:
  assumes "is_ep_cap cap" and "cap_relation cap cap'" and "cap_relation reply_cap replyCap"
  shows "
   corres dc (einvs and valid_sched and tcb_at thread and valid_cap cap and ex_nonz_cap_to thread
              and cte_wp_at (\<lambda>c. c = cap.NullCap) (thread, tcb_cnode_index 3))
             (invs' and tcb_at' thread and valid_cap' cap')
             (receive_ipc thread cap isBlocking reply_cap) (receiveIPC thread cap' isBlocking replyCap)"
  apply (insert assms)
  apply (simp add: receive_ipc_def receiveIPC_def
              split del: if_split)
  apply (case_tac cap, simp_all add: isEndpointCap_def)
  apply (rename_tac word1 word2 right)
  apply clarsimp
  apply (rule corres_guard_imp)
    sorry (*
    apply (rule corres_split [OF _ get_ep_corres])
      apply (rule corres_guard_imp)
        apply (rule corres_split [OF _ gbn_corres])
          apply (rule_tac r'="ntfn_relation" in corres_split)
             apply (rule corres_if)
               apply (clarsimp simp: ntfn_relation_def Ipc_A.isActive_def Endpoint_H.isActive_def
                              split: Structures_A.ntfn.splits Structures_H.notification.splits)
              apply clarsimp
              apply (rule complete_signal_corres)
             apply (rule_tac P="einvs and valid_sched and tcb_at thread and
                                       ep_at word1 and valid_ep ep and
                                       obj_at (\<lambda>k. k = Endpoint ep) word1
                                       and cte_wp_at (\<lambda>c. c = cap.NullCap) (thread, tcb_cnode_index 3)
                                       and ex_nonz_cap_to thread" and
                                 P'="invs' and tcb_at' thread and ep_at' word1 and
                                           valid_ep' epa"
                                 in corres_inst)
             apply (case_tac ep)
               \<comment> \<open>IdleEP\<close>
               apply (simp add: ep_relation_def)
               apply (rule corres_guard_imp)
                 apply (case_tac isBlocking; simp)
                  apply (rule corres_split [OF _ sts_corres])
                     apply (rule set_ep_corres)
                     apply (simp add: ep_relation_def)
                    apply simp
                   apply wp+
                 apply (rule corres_guard_imp, rule do_nbrecv_failed_transfer_corres, simp)
                 apply simp
                apply (clarsimp simp add: invs_def valid_state_def valid_pspace_def
               valid_tcb_state_def st_tcb_at_tcb_at)
               apply auto[1]
       \<comment> \<open>SendEP\<close>
       apply (simp add: ep_relation_def)
       apply (rename_tac list)
       apply (rule_tac F="list \<noteq> []" in corres_req)
        apply (clarsimp simp: valid_ep_def)
       apply (case_tac list, simp_all split del: if_split)[1]
       apply (rule corres_guard_imp)
         apply (rule corres_split [OF _ set_ep_corres])
            apply (rule corres_split [OF _ gts_corres])
              apply (rule_tac
                       F="\<exists>data.
                           sender_state =
                           Structures_A.thread_state.BlockedOnSend word1 data"
                       in corres_gen_asm)
              apply (clarsimp simp: isSend_def case_bool_If
                                    case_option_If if3_fold
                         split del: if_split cong: if_cong)
              apply (rule corres_split [OF _ dit_corres])
                apply (simp split del: if_split cong: if_cong)
                apply (fold dc_def)[1]
                apply (rule_tac P="valid_objs and valid_mdb and valid_list
                                        and valid_sched
                                        and cur_tcb
                                        and valid_reply_caps
                                        and pspace_aligned and pspace_distinct
                                        and st_tcb_at (Not \<circ> awaiting_reply) a
                                        and st_tcb_at (Not \<circ> halted) a
                                        and tcb_at thread and valid_reply_masters
                                        and cte_wp_at (\<lambda>c. c = cap.NullCap)
                                                      (thread, tcb_cnode_index 3)"
                            and P'="tcb_at' a and tcb_at' thread and cur_tcb'
                                              and Invariants_H.valid_queues
                                              and valid_queues'
                                              and valid_pspace'
                                              and valid_objs'
                                        and (\<lambda>s. weak_sch_act_wf (ksSchedulerAction s) s)"
                             in corres_guard_imp [OF corres_if])
                    apply (simp add: fault_rel_optionation_def)
                   apply (rule corres_if2 [OF _ setup_caller_corres sts_corres])
                           apply simp
                          apply simp
                         apply (rule corres_split [OF _ sts_corres])
                            apply (rule possibleSwitchTo_corres)
                           apply simp
                          apply (wp sts_st_tcb_at' set_thread_state_runnable_weak_valid_sched_action
                               | simp)+
                         apply (wp sts_st_tcb_at'_cases sts_valid_queues setThreadState_valid_queues'
                                   setThreadState_st_tcb
                              | simp)+
                        apply (clarsimp simp: st_tcb_at_tcb_at st_tcb_def2 valid_sched_def
                                              valid_sched_action_def)
                       apply (clarsimp split: if_split_asm)
                      apply (clarsimp | wp do_ipc_transfer_tcb_caps)+
                     apply (rule_tac Q="\<lambda>_ s. sch_act_wf (ksSchedulerAction s) s"
                           in hoare_post_imp, erule sch_act_wf_weak)
               apply (wp sts_st_tcb' gts_st_tcb_at | simp)+
                  apply (case_tac lista, simp_all add: ep_relation_def)[1]
                 apply (simp cong: list.case_cong)
                 apply wp
                apply simp
         apply (wp weak_sch_act_wf_lift_linear setEndpoint_valid_mdb' set_ep_valid_objs')
               apply (clarsimp split: list.split)
               apply (clarsimp simp add: invs_def valid_state_def st_tcb_at_tcb_at)
               apply (clarsimp simp add: valid_ep_def valid_pspace_def)
               apply (drule(1) sym_refs_obj_atD[where P="\<lambda>ko. ko = Endpoint e" for e])
               apply (fastforce simp: st_tcb_at_refs_of_rev elim: st_tcb_weakenE)
              apply (auto simp: valid_ep'_def invs'_def valid_state'_def split: list.split)[1]
             \<comment> \<open>RecvEP\<close>
             apply (simp add: ep_relation_def)
             apply (rule_tac corres_guard_imp)
               apply (case_tac isBlocking; simp)
                apply (rule corres_split [OF _ sts_corres])
                   apply (rule set_ep_corres)
                   apply (simp add: ep_relation_def)
                  apply simp
                 apply wp+
               apply (rule corres_guard_imp, rule do_nbrecv_failed_transfer_corres, simp)
               apply simp
              apply (clarsimp simp: valid_tcb_state_def)
             apply (clarsimp simp add: valid_tcb_state'_def)
            apply (rule corres_option_split[rotated 2])
              apply (rule get_ntfn_corres)
             apply clarsimp
            apply (rule corres_trivial, simp add: ntfn_relation_def default_notification_def
                                                  default_ntfn_def)
           apply (wp get_simple_ko_wp[where f=Notification] getNotification_wp gbn_wp gbn_wp'
                      hoare_vcg_all_lift hoare_vcg_imp_lift hoare_vcg_if_lift
                    | wpc | simp add: ep_at_def2[symmetric, simplified] | clarsimp)+
   apply (clarsimp simp: valid_cap_def invs_psp_aligned invs_valid_objs pred_tcb_at_def
                         valid_obj_def valid_tcb_def valid_bound_ntfn_def
                  dest!: invs_valid_objs
                  elim!: obj_at_valid_objsE
                  split: option.splits)
  apply (auto simp: valid_cap'_def invs_valid_pspace' valid_obj'_def valid_tcb'_def
                    valid_bound_ntfn'_def obj_at'_def projectKOs pred_tcb_at'_def
             dest!: invs_valid_objs' obj_at_valid_objs'
             split: option.splits)
  done *)

lemma receive_signal_corres:
 "\<lbrakk> is_ntfn_cap cap; cap_relation cap cap' \<rbrakk> \<Longrightarrow>
  corres dc (invs and st_tcb_at active thread and valid_cap cap and ex_nonz_cap_to thread)
            (invs' and tcb_at' thread and valid_cap' cap')
            (receive_signal thread cap isBlocking) (receiveSignal thread cap' isBlocking)"
  apply (simp add: receive_signal_def receiveSignal_def)
  apply (case_tac cap, simp_all add: isEndpointCap_def)
  apply (rename_tac word1 word2 rights)
  apply (rule corres_guard_imp)
    apply (rule_tac R="\<lambda>rv. invs and tcb_at thread and st_tcb_at active thread and
                            ntfn_at word1 and ex_nonz_cap_to thread and
                            valid_ntfn rv and
                            obj_at (\<lambda>k. k = Notification rv) word1" and
                            R'="\<lambda>rv'. invs' and tcb_at' thread and ntfn_at' word1 and
                            valid_ntfn' rv'"
                         in corres_split [OF _ get_ntfn_corres])
      apply clarsimp
      apply (case_tac "ntfn_obj rv")
        \<comment> \<open>IdleNtfn\<close>
        apply (simp add: ntfn_relation_def)
        apply (rule corres_guard_imp)
          apply (case_tac isBlocking; simp)
           apply (rule corres_split [OF _ sts_corres])
              sorry (*
              apply (rule set_ntfn_corres)
              apply (simp add: ntfn_relation_def)
             apply simp
            apply wp+
          apply (rule corres_guard_imp, rule do_nbrecv_failed_transfer_corres, simp+)
       \<comment> \<open>WaitingNtfn\<close>
       apply (simp add: ntfn_relation_def)
       apply (rule corres_guard_imp)
         apply (case_tac isBlocking; simp)
          apply (rule corres_split[OF _ sts_corres])
             apply (rule set_ntfn_corres)
             apply (simp add: ntfn_relation_def)
            apply simp
           apply wp+
         apply (rule corres_guard_imp)
           apply (rule do_nbrecv_failed_transfer_corres, simp+)
      \<comment> \<open>ActiveNtfn\<close>
      apply (simp add: ntfn_relation_def)
      apply (rule corres_guard_imp)
        apply (simp add: badgeRegister_def badge_register_def)
        apply (rule corres_split [OF _ user_setreg_corres])
          apply (rule set_ntfn_corres)
          apply (simp add: ntfn_relation_def)
         apply wp+
       apply (fastforce simp: invs_def valid_state_def valid_pspace_def
                       elim!: st_tcb_weakenE)
      apply (clarsimp simp: invs'_def valid_state'_def valid_pspace'_def)
     apply wp+
   apply (clarsimp simp add: ntfn_at_def2 valid_cap_def st_tcb_at_tcb_at)
  apply (clarsimp simp add: valid_cap'_def)
  done *)

lemma tg_sp':
  "\<lbrace>P\<rbrace> threadGet f p \<lbrace>\<lambda>t. obj_at' (\<lambda>t'. f t' = t) p and P\<rbrace>"
  including no_pre
  apply (simp add: threadGet_def)
  apply wp
  apply (rule hoare_strengthen_post)
   apply (rule getObject_tcb_sp)
  apply clarsimp
  apply (erule obj_at'_weakenE)
  apply simp
  done

declare lookup_cap_valid' [wp]

lemma send_fault_ipc_corres:
  "\<lbrakk> valid_fault f; fr f f'; cap_relation fc fc' \<rbrakk> \<Longrightarrow>
  corres (fr \<oplus> dc)
         (einvs and st_tcb_at active thread and ex_nonz_cap_to thread)
         (invs' and sch_act_not thread and tcb_at' thread)
         (send_fault_ipc thread fc f can_donate) (sendFaultIPC thread fc' f' can_donate)"
  apply (simp add: send_fault_ipc_def sendFaultIPC_def
                   liftE_bindE Let_def)
  apply (rule corres_guard_imp)
  sorry (*
    apply (rule corres_split [where r'="\<lambda>fh fh'. fh = to_bl fh'"])
       apply simp
       apply (rule corres_splitEE)
          prefer 2
          apply (rule corres_cap_fault)
          apply (rule lookup_cap_corres, rule refl)
         apply (rule_tac P="einvs and st_tcb_at active thread
                                 and valid_cap handler_cap and ex_nonz_cap_to thread"
                     and P'="invs' and tcb_at' thread and sch_act_not thread
                                   and valid_cap' handlerCap"
                     in corres_inst)
         apply (case_tac handler_cap,
                simp_all add: isCap_defs lookup_failure_map_def
                              case_bool_If If_rearrage
                   split del: if_split cong: if_cong)[1]
          apply (rule corres_guard_imp)
            apply (rule corres_if2 [OF refl])
             apply (simp add: dc_def[symmetric])
             apply (rule corres_split [OF send_ipc_corres threadset_corres], simp_all)[1]
               apply (simp add: tcb_relation_def fault_rel_optionation_def exst_same_def)+
              apply (wp thread_set_invs_trivial thread_set_no_change_tcb_state
                        thread_set_typ_at ep_at_typ_at ex_nonz_cap_to_pres
                        thread_set_cte_wp_at_trivial thread_set_not_state_valid_sched
                   | simp add: tcb_cap_cases_def)+
             apply ((wp threadSet_invs_trivial threadSet_tcb'
                   | simp add: tcb_cte_cases_def
                   | wp (once) sch_act_sane_lift)+)[1]
            apply (rule corres_trivial, simp add: lookup_failure_map_def)
           apply (clarsimp simp: st_tcb_at_tcb_at split: if_split)
           apply (simp add: valid_cap_def)
          apply (clarsimp simp: valid_cap'_def inQ_def)
          apply auto[1]
         apply (clarsimp simp: lookup_failure_map_def)
        apply wp+
      apply (rule threadget_corres)
      apply (simp add: tcb_relation_def)
     apply wp+
   apply (fastforce elim: st_tcb_at_tcb_at)
  apply fastforce
  done *)

lemma gets_the_noop_corres:
  assumes P: "\<And>s. P s \<Longrightarrow> f s \<noteq> None"
  shows "corres dc P P' (gets_the f) (return x)"
  apply (clarsimp simp: corres_underlying_def gets_the_def
                        return_def gets_def bind_def get_def)
  apply (clarsimp simp: assert_opt_def return_def dest!: P)
  done

lemma tcbEPFindIndex_inv[wp]:
  "tcbEPFindIndex t q i \<lbrace>P\<rbrace>"
  sorry

crunches sendFaultIPC, receiveIPC, receiveSignal
  for typ_at'[wp]: "\<lambda>s. P (typ_at' T p s)"
  (wp: crunch_wps hoare_vcg_all_lift whileM_inv simp: crunch_simps)

lemmas sendFaultIPC_typ_ats[wp] = typ_at_lifts [OF sendFaultIPC_typ_at']
lemmas receiveIPC_typ_ats[wp] = typ_at_lifts [OF receiveIPC_typ_at']
lemmas receiveAIPC_typ_ats[wp] = typ_at_lifts [OF receiveSignal_typ_at']

lemma setCTE_valid_queues[wp]:
  "\<lbrace>Invariants_H.valid_queues\<rbrace> setCTE ptr val \<lbrace>\<lambda>rv. Invariants_H.valid_queues\<rbrace>"
  by (wp valid_queues_lift setCTE_pred_tcb_at')

crunch vq[wp]: cteInsert "Invariants_H.valid_queues"
  (wp: crunch_wps)

lemma getSlotCap_cte_wp_at:
  "\<lbrace>\<top>\<rbrace> getSlotCap sl \<lbrace>\<lambda>rv. cte_wp_at' (\<lambda>c. cteCap c = rv) sl\<rbrace>"
  apply (simp add: getSlotCap_def)
  apply (wp getCTE_wp)
  apply (clarsimp simp: cte_wp_at_ctes_of)
  done

crunch no_0_obj'[wp]: setThreadState no_0_obj'

declare haskell_assert_inv[wp del]

lemma cteInsert_cap_to':
  "\<lbrace>ex_nonz_cap_to' p and cte_wp_at' (\<lambda>c. cteCap c = NullCap) dest\<rbrace>
     cteInsert cap src dest
   \<lbrace>\<lambda>rv. ex_nonz_cap_to' p\<rbrace>"
  apply (simp    add: cteInsert_def ex_nonz_cap_to'_def
                      updateCap_def setUntypedCapAsFull_def
           split del: if_split)
  apply (rule hoare_pre, rule hoare_vcg_ex_lift)
   apply (wp updateMDB_weak_cte_wp_at
             setCTE_weak_cte_wp_at
           | simp
           | rule hoare_drop_imps)+
  apply (wp getCTE_wp)
  apply clarsimp
  apply (rule_tac x=cref in exI)
  apply (rule conjI)
   apply (clarsimp simp: cte_wp_at_ctes_of)+
  done

crunches setExtraBadge, doIPCTransfer
  for cap_to'[wp]: "ex_nonz_cap_to' p"
  (ignore: transferCapsToSlots
       wp: crunch_wps transferCapsToSlots_pres2 cteInsert_cap_to' hoare_vcg_const_Ball_lift
     simp: zipWithM_x_mapM ball_conj_distrib)

lemma st_tcb_idle':
  "\<lbrakk>valid_idle' s; st_tcb_at' P t s\<rbrakk> \<Longrightarrow>
   (t = ksIdleThread s) \<longrightarrow> P IdleThreadState"
  by (clarsimp simp: valid_idle'_def pred_tcb_at'_def obj_at'_def idle_tcb'_def)


crunches setExtraBadge, receiveIPC
  for it[wp]: "\<lambda>s. P (ksIdleThread s)"
  and irqs_masked' [wp]: "irqs_masked'"
  (ignore: transferCapsToSlots
       wp: transferCapsToSlots_pres2 crunch_wps hoare_vcg_all_lift
     simp: crunch_simps ball_conj_distrib)

crunches copyMRs, doIPCTransfer
  for ksQ'[wp]: "\<lambda>s. P (ksReadyQueues s)"
  and ct'[wp]: "\<lambda>s. P (ksCurThread s)"
  (wp: mapM_wp' hoare_drop_imps simp: crunch_simps)

lemma asUser_ct_not_inQ[wp]:
  "\<lbrace>ct_not_inQ\<rbrace> asUser t m \<lbrace>\<lambda>rv. ct_not_inQ\<rbrace>"
  apply (simp add: asUser_def split_def)
  apply (wp hoare_drop_imps threadSet_not_inQ | simp)+
  done

crunches copyMRs, doIPCTransfer
  for ct_not_inQ[wp]: "ct_not_inQ"
  (wp: mapM_wp' hoare_drop_imps simp: crunch_simps)

lemma ntfn_q_refs_no_bound_refs':
  "rf : ntfn_q_refs_of' (ntfnObj ob) \<Longrightarrow> rf ~: ntfn_bound_refs' (ntfnBoundTCB ob')"
  by (auto simp add: ntfn_q_refs_of'_def ntfn_bound_refs'_def
           split: Structures_H.ntfn.splits)

lemma completeSignal_invs:
  "\<lbrace>invs' and tcb_at' tcb\<rbrace>
     completeSignal ntfnptr tcb
   \<lbrace>\<lambda>_. invs'\<rbrace>"
  apply (simp add: completeSignal_def)
  apply (rule hoare_seq_ext[OF _ get_ntfn_sp'])
  apply (rule hoare_pre)
   apply (wp set_ntfn_minor_invs' | wpc | simp)+
    apply (rule_tac Q="\<lambda>_ s. (state_refs_of' s ntfnptr = ntfn_bound_refs' (ntfnBoundTCB ntfn))
                           \<and> ntfn_at' ntfnptr s
                           \<and> valid_ntfn' (ntfnObj_update (\<lambda>_. Structures_H.ntfn.IdleNtfn) ntfn) s
                           \<and> ((\<exists>y. ntfnBoundTCB ntfn = Some y) \<longrightarrow> ex_nonz_cap_to' ntfnptr s)
                           \<and> ntfnptr \<noteq> ksIdleThread s"
                          in hoare_strengthen_post)
     apply ((wp hoare_vcg_ex_lift static_imp_wp | wpc | simp add: valid_ntfn'_def)+)[1]
    apply (clarsimp simp: obj_at'_def state_refs_of'_def typ_at'_def ko_wp_at'_def  projectKOs split: option.splits)
  sorry (*
    apply (blast dest: ntfn_q_refs_no_bound_refs')
   apply wp
  apply (subgoal_tac "valid_ntfn' ntfn s")
   apply (subgoal_tac "ntfnptr \<noteq> ksIdleThread s")
    apply (fastforce simp: valid_ntfn'_def valid_bound_tcb'_def projectKOs ko_at_state_refs_ofD'
                     elim: obj_at'_weakenE
                           if_live_then_nonz_capD'[OF invs_iflive'
                                                      obj_at'_real_def[THEN meta_eq_to_obj_eq,
                                                                       THEN iffD1]])
   apply (fastforce simp: valid_idle'_def pred_tcb_at'_def obj_at'_def projectKOs
                   dest!: invs_valid_idle')
  apply (fastforce dest: invs_valid_objs' ko_at_valid_objs'
                   simp: valid_obj'_def projectKOs)[1]
  done *)

lemmas threadSet_urz = untyped_ranges_zero_lift[where f="cteCaps_of", OF _ threadSet_cteCaps_of]

lemma setSchedContext_urz[wp]:
  "setSchedContext p sc \<lbrace> untyped_ranges_zero' \<rbrace>"
  sorry

crunches doIPCTransfer
  for urz[wp]: "untyped_ranges_zero'"
  (ignore: threadSet wp: threadSet_urz crunch_wps simp: zipWithM_x_mapM)

crunches receiveIPC
  for gsUntypedZeroRanges[wp]: "\<lambda>s. P (gsUntypedZeroRanges s)"
  (wp: crunch_wps transferCapsToSlots_pres1 hoare_vcg_all_lift whileM_inv
   simp: crunch_simps zipWithM_x_mapM ignore: constOnFailure)

lemmas possibleSwitchToTo_cteCaps_of[wp]
    = cteCaps_of_ctes_of_lift[OF possibleSwitchTo_ctes_of]

(* t = ksCurThread s *)
lemma ri_invs' [wp]:
  "\<lbrace>invs' and sch_act_not t
          and ct_in_state' simple'
          and st_tcb_at' simple' t
          and (\<lambda>s. \<forall>p. t \<notin> set (ksReadyQueues s p))
          and ex_nonz_cap_to' t
          and (\<lambda>s. \<forall>r \<in> zobj_refs' cap. ex_nonz_cap_to' r s)\<rbrace>
  receiveIPC t cap isBlocking replyCap
  \<lbrace>\<lambda>_. invs'\<rbrace>" (is "\<lbrace>?pre\<rbrace> _ \<lbrace>_\<rbrace>")
  apply (clarsimp simp: receiveIPC_def)
  sorry (*
  apply (rule hoare_seq_ext [OF _ get_ep_sp'])
  apply (rule hoare_seq_ext [OF _ gbn_sp'])
  apply (rule hoare_seq_ext)
  (* set up precondition for old proof *)
   apply (rule_tac R="ko_at' ep (capEPPtr cap) and ?pre" in hoare_vcg_if_split)
    apply (wp completeSignal_invs)
   apply (case_tac ep)
     \<comment> \<open>endpoint = RecvEP\<close>
     apply (simp add: invs'_def valid_state'_def)
     apply (rule hoare_pre, wpc, wp valid_irq_node_lift)
      apply (simp add: valid_ep'_def)
      apply (wp sts_sch_act' hoare_vcg_const_Ball_lift valid_irq_node_lift
                sts_valid_queues setThreadState_ct_not_inQ
                asUser_urz
           | simp add: doNBRecvFailedTransfer_def cteCaps_of_def)+
     apply (clarsimp simp: valid_tcb_state'_def pred_tcb_at' o_def)
     apply (rule conjI, clarsimp elim!: obj_at'_weakenE)
     apply (frule obj_at_valid_objs')
      apply (clarsimp simp: valid_pspace'_def)
     apply (drule(1) sym_refs_ko_atD')
     apply (drule simple_st_tcb_at_state_refs_ofD')
     apply (drule bound_tcb_at_state_refs_ofD')
     apply (clarsimp simp: st_tcb_at_refs_of_rev' valid_ep'_def
                           valid_obj'_def projectKOs tcb_bound_refs'_def
                    dest!: isCapDs)
     apply (rule conjI, clarsimp)
      apply (drule (1) bspec)
      apply (clarsimp dest!: st_tcb_at_state_refs_ofD')
      apply (clarsimp simp: set_eq_subset)
     apply (rule conjI, erule delta_sym_refs)
       apply (clarsimp split: if_split_asm)
        apply (rename_tac list one two three fur five six seven eight nine ten eleven)
        apply (subgoal_tac "set list \<times> {EPRecv} \<noteq> {}")
         apply (thin_tac "\<forall>a b. t \<notin> set (ksReadyQueues one (a, b))") \<comment> \<open>causes slowdown\<close>
         apply (safe ; solves \<open>auto\<close>)
        apply fastforce
       apply fastforce
      apply (clarsimp split: if_split_asm)
     apply (fastforce simp: valid_pspace'_def global'_no_ex_cap idle'_not_queued)
   \<comment> \<open>endpoint = IdleEP\<close>
    apply (simp add: invs'_def valid_state'_def)
    apply (rule hoare_pre, wpc, wp valid_irq_node_lift)
     apply (simp add: valid_ep'_def)
     apply (wp sts_sch_act' valid_irq_node_lift
               sts_valid_queues setThreadState_ct_not_inQ
               asUser_urz
          | simp add: doNBRecvFailedTransfer_def cteCaps_of_def)+
    apply (clarsimp simp: pred_tcb_at' valid_tcb_state'_def o_def)
    apply (rule conjI, clarsimp elim!: obj_at'_weakenE)
    apply (subgoal_tac "t \<noteq> capEPPtr cap")
     apply (drule simple_st_tcb_at_state_refs_ofD')
     apply (drule ko_at_state_refs_ofD')
     apply (drule bound_tcb_at_state_refs_ofD')
     apply (clarsimp dest!: isCapDs)
     apply (rule conjI, erule delta_sym_refs)
       apply (clarsimp split: if_split_asm)
      apply (clarsimp simp: tcb_bound_refs'_def
                      dest: symreftype_inverse'
                     split: if_split_asm)
     apply (fastforce simp: global'_no_ex_cap)
    apply (clarsimp simp: obj_at'_def pred_tcb_at'_def projectKOs)
   \<comment> \<open>endpoint = SendEP\<close>
   apply (simp add: invs'_def valid_state'_def)
   apply (rename_tac list)
   apply (case_tac list, simp_all split del: if_split)
   apply (rename_tac sender queue)
   apply (rule hoare_pre)
    apply (wp valid_irq_node_lift hoare_drop_imps setEndpoint_valid_mdb'
              set_ep_valid_objs' sts_st_tcb' sts_sch_act' sts_valid_queues
              setThreadState_ct_not_inQ possibleSwitchTo_valid_queues
              possibleSwitchTo_valid_queues'
              possibleSwitchTo_ct_not_inQ hoare_vcg_all_lift
              setEndpoint_ksQ setEndpoint_ct'
         | simp add: valid_tcb_state'_def case_bool_If
                     case_option_If
              split del: if_split cong: if_cong
        | wp (once) sch_act_sane_lift hoare_vcg_conj_lift hoare_vcg_all_lift
                  untyped_ranges_zero_lift)+
   apply (clarsimp split del: if_split simp: pred_tcb_at')
   apply (frule obj_at_valid_objs')
    apply (clarsimp simp: valid_pspace'_def)
   apply (frule(1) ct_not_in_epQueue, clarsimp, clarsimp)
   apply (drule(1) sym_refs_ko_atD')
   apply (drule simple_st_tcb_at_state_refs_ofD')
   apply (clarsimp simp: projectKOs valid_obj'_def valid_ep'_def
                         st_tcb_at_refs_of_rev' conj_ac
              split del: if_split
                   cong: if_cong)
   apply (frule_tac t=sender in valid_queues_not_runnable'_not_ksQ)
    apply (erule pred_tcb'_weakenE, clarsimp)
   apply (subgoal_tac "sch_act_not sender s")
    prefer 2
    apply (clarsimp simp: pred_tcb_at'_def obj_at'_def)
   apply (drule st_tcb_at_state_refs_ofD')
   apply (simp only: conj_ac(1, 2)[where Q="sym_refs R" for R])
   apply (subgoal_tac "distinct (ksIdleThread s # capEPPtr cap # t # sender # queue)")
    apply (rule conjI)
     apply (clarsimp simp: ep_redux_simps' cong: if_cong)
     apply (erule delta_sym_refs)
      apply (clarsimp split: if_split_asm)
     apply (fastforce simp: tcb_bound_refs'_def
                      dest: symreftype_inverse'
                     split: if_split_asm)
    apply (clarsimp simp: singleton_tuple_cartesian split: list.split
            | rule conjI | drule(1) bspec
            | drule st_tcb_at_state_refs_ofD' bound_tcb_at_state_refs_ofD'
            | clarsimp elim!: if_live_state_refsE)+
    apply (case_tac cap, simp_all add: isEndpointCap_def)
    apply (clarsimp simp: global'_no_ex_cap)
   apply (rule conjI
           | clarsimp simp: singleton_tuple_cartesian split: list.split
           | clarsimp elim!: if_live_state_refsE
           | clarsimp simp: global'_no_ex_cap idle'_not_queued' idle'_only_sc_refs tcb_bound_refs'_def
           | drule(1) bspec | drule st_tcb_at_state_refs_ofD'
           | clarsimp simp: set_eq_subset dest!: bound_tcb_at_state_refs_ofD' )+
  apply (rule hoare_pre)
   apply (wp getNotification_wp | wpc | clarsimp)+
  done
  *)

(* t = ksCurThread s *)
lemma rai_invs'[wp]:
  "\<lbrace>invs' and sch_act_not t
          and st_tcb_at' simple' t
          and (\<lambda>s. \<forall>p. t \<notin> set (ksReadyQueues s p))
          and ex_nonz_cap_to' t
          and (\<lambda>s. \<forall>r \<in> zobj_refs' cap. ex_nonz_cap_to' r s)
          and (\<lambda>s. \<exists>ntfnptr. isNotificationCap cap
                 \<and> capNtfnPtr cap = ntfnptr
                 \<and> obj_at' (\<lambda>ko. ntfnBoundTCB ko = None \<or> ntfnBoundTCB ko = Some t)
                           ntfnptr s)\<rbrace>
    receiveSignal t cap isBlocking
   \<lbrace>\<lambda>_. invs'\<rbrace>"
  apply (simp add: receiveSignal_def)
  apply (rule hoare_seq_ext [OF _ get_ntfn_sp'])
  apply (rename_tac ep)
  apply (case_tac "ntfnObj ep")
    \<comment> \<open>ep = IdleNtfn\<close>
    apply (simp add: invs'_def valid_state'_def)
    apply (rule hoare_pre)
     apply (wp valid_irq_node_lift sts_sch_act' typ_at_lifts
               sts_valid_queues setThreadState_ct_not_inQ
               asUser_urz
            | simp add: valid_ntfn'_def doNBRecvFailedTransfer_def | wpc)+
  sorry (*
    apply (clarsimp simp: pred_tcb_at' valid_tcb_state'_def)
    apply (rule conjI, clarsimp elim!: obj_at'_weakenE)
    apply (subgoal_tac "capNtfnPtr cap \<noteq> t")
     apply (frule valid_pspace_valid_objs')
     apply (frule (1) ko_at_valid_objs')
      apply (clarsimp simp: projectKOs)
     apply (clarsimp simp: valid_obj'_def valid_ntfn'_def)
     apply (rule conjI, clarsimp simp: obj_at'_def split: option.split)
     apply (drule simple_st_tcb_at_state_refs_ofD'
                  ko_at_state_refs_ofD' bound_tcb_at_state_refs_ofD')+
     apply (clarsimp dest!: isCapDs)
     apply (rule conjI, erule delta_sym_refs)
       apply (clarsimp split: if_split_asm)
      apply (fastforce simp: tcb_bound_refs'_def symreftype_inverse'
                      split: if_split_asm)
     apply (clarsimp dest!: global'_no_ex_cap)
    apply (clarsimp simp: pred_tcb_at'_def obj_at'_def projectKOs)
   \<comment> \<open>ep = ActiveNtfn\<close>
   apply (simp add: invs'_def valid_state'_def)
   apply (rule hoare_pre)
    apply (wp valid_irq_node_lift sts_valid_objs' typ_at_lifts static_imp_wp
              asUser_urz
         | simp add: valid_ntfn'_def)+
   apply (clarsimp simp: pred_tcb_at' valid_pspace'_def)
   apply (frule (1) ko_at_valid_objs')
    apply (clarsimp simp: projectKOs)
   apply (clarsimp simp: valid_obj'_def valid_ntfn'_def isCap_simps)
   apply (drule simple_st_tcb_at_state_refs_ofD'
                 ko_at_state_refs_ofD')+
   apply (erule delta_sym_refs)
    apply (clarsimp split: if_split_asm simp: global'_no_ex_cap)+
  \<comment> \<open>ep = WaitingNtfn\<close>
  apply (simp add: invs'_def valid_state'_def)
  apply (rule hoare_pre)
   apply (wp hoare_vcg_const_Ball_lift valid_irq_node_lift sts_sch_act'
             sts_valid_queues setThreadState_ct_not_inQ typ_at_lifts
             asUser_urz
        | simp add: valid_ntfn'_def doNBRecvFailedTransfer_def | wpc)+
  apply (clarsimp simp: valid_tcb_state'_def)
  apply (frule_tac t=t in not_in_ntfnQueue)
     apply (simp)
    apply (simp)
   apply (erule pred_tcb'_weakenE, clarsimp)
  apply (frule ko_at_valid_objs')
    apply (clarsimp simp: valid_pspace'_def)
   apply (simp add: projectKOs)
  apply (clarsimp simp: valid_obj'_def)
  apply (clarsimp simp: valid_ntfn'_def pred_tcb_at')
  apply (rule conjI, clarsimp elim!: obj_at'_weakenE)
  apply (rule conjI, clarsimp simp: obj_at'_def split: option.split)
  apply (drule(1) sym_refs_ko_atD')
  apply (drule simple_st_tcb_at_state_refs_ofD')
  apply (drule bound_tcb_at_state_refs_ofD')
  apply (clarsimp simp: st_tcb_at_refs_of_rev'
                 dest!: isCapDs)
  apply (rule conjI, erule delta_sym_refs)
    apply (clarsimp split: if_split_asm)
    apply (rename_tac list one two three four five six seven eight nine)
    apply (subgoal_tac "set list \<times> {NTFNSignal} \<noteq> {}")
     apply safe[1]
        apply (auto simp: symreftype_inverse' ntfn_bound_refs'_def tcb_bound_refs'_def)[5]
   apply (fastforce simp: tcb_bound_refs'_def
                   split: if_split_asm)
  apply (clarsimp dest!: global'_no_ex_cap)
  done *)

lemma getCTE_cap_to_refs[wp]:
  "\<lbrace>\<top>\<rbrace> getCTE p \<lbrace>\<lambda>rv s. \<forall>r\<in>zobj_refs' (cteCap rv). ex_nonz_cap_to' r s\<rbrace>"
  apply (rule hoare_strengthen_post [OF getCTE_sp])
  apply (clarsimp simp: ex_nonz_cap_to'_def)
  apply (fastforce elim: cte_wp_at_weakenE')
  done

lemma lookupCap_cap_to_refs[wp]:
  "\<lbrace>\<top>\<rbrace> lookupCap t cref \<lbrace>\<lambda>rv s. \<forall>r\<in>zobj_refs' rv. ex_nonz_cap_to' r s\<rbrace>,-"
  apply (simp add: lookupCap_def lookupCapAndSlot_def split_def
                   getSlotCap_def)
  apply (wp | simp)+
  done

lemma arch_stt_objs' [wp]:
  "\<lbrace>valid_objs'\<rbrace> Arch.switchToThread t \<lbrace>\<lambda>rv. valid_objs'\<rbrace>"
  apply (simp add: ARM_H.switchToThread_def)
  apply wp
  done

declare zipWithM_x_mapM [simp]

lemma cteInsert_ct'[wp]:
  "\<lbrace>cur_tcb'\<rbrace> cteInsert a b c \<lbrace>\<lambda>rv. cur_tcb'\<rbrace>"
  by (wp sch_act_wf_lift valid_queues_lift cur_tcb_lift tcb_in_cur_domain'_lift)

lemma possibleSwitchTo_sch_act_not:
  "\<lbrace>sch_act_not t' and K (t \<noteq> t')\<rbrace> possibleSwitchTo t \<lbrace>\<lambda>rv. sch_act_not t'\<rbrace>"
  apply (simp add: possibleSwitchTo_def setSchedulerAction_def curDomain_def)
  apply (wp hoare_drop_imps | wpc | simp)+
  sorry


lemma si_invs'[wp]:
  "\<lbrace>invs' and st_tcb_at' simple' t
          and (\<lambda>s. \<forall>p. t \<notin> set (ksReadyQueues s p))
          and sch_act_not t
          and ex_nonz_cap_to' ep and ex_nonz_cap_to' t\<rbrace>
  sendIPC bl call ba cg cgr cd t ep
  \<lbrace>\<lambda>rv. invs'\<rbrace>"
  supply if_split[split del]
  apply (simp add: sendIPC_def)
  apply (rule hoare_seq_ext [OF _ get_ep_sp'])
  apply (case_tac epa)
    \<comment> \<open>epa = RecvEP\<close>
    apply simp
    apply (rename_tac list)
    apply (case_tac list)
     apply simp
    apply (simp add: invs'_def valid_state'_def)
    apply (rule hoare_pre)
     apply (rule_tac P="a\<noteq>t" in hoare_gen_asm)
  sorry (*
     apply (wp valid_irq_node_lift
               sts_valid_objs' set_ep_valid_objs' set_ep'.valid_mdb' sts_st_tcb' sts_sch_act'
               possibleSwitchTo_sch_act_not sts_valid_queues setThreadState_ct_not_inQ
               possibleSwitchTo_ksQ' possibleSwitchTo_ct_not_inQ hoare_vcg_all_lift sts_ksQ'
               hoare_convert_imp [OF doIPCTransfer_sch_act doIPCTransfer_ct']
               hoare_convert_imp [OF set_ep'.ksSchedulerAction set_ep'.ct]
               hoare_drop_imp [where f="threadGet tcbFault t"]
             | rule_tac f="getThreadState a" in hoare_drop_imp
             | wp (once) hoare_drop_imp[where R="\<lambda>_ _. call"]
               hoare_drop_imp[where R="\<lambda>_ _. \<not> call"]
               hoare_drop_imp[where R="\<lambda>_ _. cg"]
             | simp    add: valid_tcb_state'_def case_bool_If
                            case_option_If
                      cong: if_cong
             | wp (once) sch_act_sane_lift tcb_in_cur_domain'_lift hoare_vcg_const_imp_lift)+
    apply (clarsimp simp: pred_tcb_at' cong: conj_cong imp_cong)
    apply (frule obj_at_valid_objs', clarsimp)
    apply (frule(1) sym_refs_ko_atD')
    apply (clarsimp simp: projectKOs valid_obj'_def valid_ep'_def
                          st_tcb_at_refs_of_rev' pred_tcb_at'
                          conj_comms fun_upd_def[symmetric]
               split del: if_split)
    apply (frule pred_tcb_at')
    apply (drule simple_st_tcb_at_state_refs_ofD' st_tcb_at_state_refs_ofD')+
    apply (clarsimp simp: valid_pspace'_splits)
    apply (subst fun_upd_idem[where x=t])
     apply (clarsimp split: if_split)
     apply (rule conjI, clarsimp simp: obj_at'_def projectKOs)
     apply (drule bound_tcb_at_state_refs_ofD')
     apply (fastforce simp: tcb_bound_refs'_def)
    apply (subgoal_tac "ex_nonz_cap_to' a s")
     prefer 2
     apply (clarsimp elim!: if_live_state_refsE)
    apply clarsimp
    apply (rule conjI)
     apply (drule bound_tcb_at_state_refs_ofD')
     apply (fastforce simp: tcb_bound_refs'_def set_eq_subset)
    apply (clarsimp simp: conj_ac)
    apply (rule conjI, clarsimp simp: idle'_only_sc_refs)
    apply (rule conjI, clarsimp simp: global'_no_ex_cap)
    apply (rule conjI)
     apply (rule impI)
     apply (frule(1) ct_not_in_epQueue, clarsimp, clarsimp)
     apply (clarsimp)
    apply (simp add: ep_redux_simps')
    apply (rule conjI, clarsimp split: if_split)
     apply (rule conjI, fastforce simp: tcb_bound_refs'_def set_eq_subset)
     apply (clarsimp, erule delta_sym_refs;
            solves\<open>auto simp: symreftype_inverse' tcb_bound_refs'_def split: if_split_asm\<close>)
    apply (solves\<open>clarsimp split: list.splits\<close>)
   \<comment> \<open>epa = IdleEP\<close>
   apply (cases bl)
    apply (simp add: invs'_def valid_state'_def)
    apply (rule hoare_pre, wp valid_irq_node_lift)
     apply (simp add: valid_ep'_def)
     apply (wp valid_irq_node_lift sts_sch_act' sts_valid_queues
               setThreadState_ct_not_inQ)
    apply (clarsimp simp: valid_tcb_state'_def pred_tcb_at')
    apply (rule conjI, clarsimp elim!: obj_at'_weakenE)
    apply (subgoal_tac "ep \<noteq> t")
     apply (drule simple_st_tcb_at_state_refs_ofD' ko_at_state_refs_ofD'
                  bound_tcb_at_state_refs_ofD')+
     apply (rule conjI, erule delta_sym_refs)
       apply (auto simp: tcb_bound_refs'_def symreftype_inverse'
                  split: if_split_asm)[2]
     apply (fastforce simp: global'_no_ex_cap)
    apply (clarsimp simp: pred_tcb_at'_def obj_at'_def projectKOs)
   apply simp
   apply wp
   apply simp
  \<comment> \<open>epa = SendEP\<close>
  apply (cases bl)
   apply (simp add: invs'_def valid_state'_def)
   apply (rule hoare_pre, wp valid_irq_node_lift)
    apply (simp add: valid_ep'_def)
    apply (wp hoare_vcg_const_Ball_lift valid_irq_node_lift sts_sch_act'
              sts_valid_queues setThreadState_ct_not_inQ)
   apply (clarsimp simp: valid_tcb_state'_def pred_tcb_at')
   apply (rule conjI, clarsimp elim!: obj_at'_weakenE)
   apply (frule obj_at_valid_objs', clarsimp)
   apply (frule(1) sym_refs_ko_atD')
   apply (frule pred_tcb_at')
   apply (drule simple_st_tcb_at_state_refs_ofD')
   apply (drule bound_tcb_at_state_refs_ofD')
   apply (clarsimp simp: valid_obj'_def valid_ep'_def
                         projectKOs st_tcb_at_refs_of_rev')
   apply (rule conjI, clarsimp)
    apply (drule (1) bspec)
    apply (clarsimp dest!: st_tcb_at_state_refs_ofD' bound_tcb_at_state_refs_ofD'
                     simp: tcb_bound_refs'_def)
    apply (clarsimp simp: set_eq_subset)
   apply (rule conjI, erule delta_sym_refs)
     subgoal by (fastforce simp: obj_at'_def projectKOs symreftype_inverse'
                     split: if_split_asm)
    apply (fastforce simp: tcb_bound_refs'_def symreftype_inverse'
                    split: if_split_asm)
   apply (fastforce simp: global'_no_ex_cap idle'_not_queued)
  apply (simp | wp)+
  done *)

lemma sfi_invs_plus':
  "\<lbrace>invs' and st_tcb_at' simple' t
          and sch_act_not t
          and (\<lambda>s. \<forall>p. t \<notin> set (ksReadyQueues s p))
          and ex_nonz_cap_to' t\<rbrace>
      sendFaultIPC t cap f canDonate
   \<lbrace>\<lambda>rv. invs'\<rbrace>, \<lbrace>\<lambda>rv. invs' and st_tcb_at' simple' t
                      and (\<lambda>s. \<forall>p. t \<notin> set (ksReadyQueues s p))
                      and sch_act_not t and (\<lambda>s. ksIdleThread s \<noteq> t)\<rbrace>"
  apply (simp add: sendFaultIPC_def)
  apply (wp threadSet_invs_trivial threadSet_pred_tcb_no_state
            threadSet_cap_to'
           | wpc | simp)+
  sorry (*
   apply (rule_tac Q'="\<lambda>rv s. invs' s \<and> sch_act_not t s
                             \<and> st_tcb_at' simple' t s
                             \<and> (\<forall>p. t \<notin> set (ksReadyQueues s p))
                             \<and> ex_nonz_cap_to' t s
                             \<and> t \<noteq> ksIdleThread s
                             \<and> (\<forall>r\<in>zobj_refs' rv. ex_nonz_cap_to' r s)"
                 in hoare_post_imp_R)
    apply wp
   apply (clarsimp simp: inQ_def pred_tcb_at')
  apply (wp | simp)+
  apply (clarsimp simp: eq_commute)
  apply (subst(asm) global'_no_ex_cap, auto)
  done *)

lemma hf_corres:
  "fr f f' \<Longrightarrow>
   corres dc (einvs and  st_tcb_at active thread and ex_nonz_cap_to thread
                   and (%_. valid_fault f))
             (invs' and sch_act_not thread
                    and (\<lambda>s. \<forall>p. thread \<notin> set(ksReadyQueues s p))
                    and st_tcb_at' simple' thread and ex_nonz_cap_to' thread)
             (handle_fault thread f) (handleFault thread f')"
  apply (simp add: handle_fault_def handleFault_def)
  apply (rule corres_guard_imp)
    apply (subst return_bind [symmetric],
               rule corres_split [where P="tcb_at thread",
                                  OF _ gets_the_noop_corres [where x="()"]])
  sorry (*
       apply (rule corres_split_catch)
          apply (rule hdf_corres)
          apply (rule_tac F="valid_fault f" in corres_gen_asm)
         apply (rule send_fault_ipc_corres, assumption)
         apply simp
        apply wp+
       apply (rule hoare_post_impErr, rule sfi_invs_plus', simp_all)[1]
       apply clarsimp
      apply (simp add: tcb_at_def)
     apply wp+
   apply (clarsimp simp: st_tcb_at_tcb_at st_tcb_def2 invs_def
                         valid_state_def valid_idle_def)
  apply auto
  done *)

lemma sts_invs_minor'':
  "\<lbrace>st_tcb_at' (\<lambda>st'. tcb_st_refs_of' st' = tcb_st_refs_of' st
                   \<and> (st \<noteq> Inactive \<and> \<not> idle' st \<longrightarrow>
                      st' \<noteq> Inactive \<and> \<not> idle' st')) t
      and (\<lambda>s. t = ksIdleThread s \<longrightarrow> idle' st)
      and (\<lambda>s. (\<exists>p. t \<in> set (ksReadyQueues s p)) \<longrightarrow> runnable' st)
      and (\<lambda>s. runnable' st \<and> obj_at' tcbQueued t s
                                      \<longrightarrow> st_tcb_at' runnable' t s)
      and (\<lambda>s. \<not> runnable' st \<longrightarrow> sch_act_not t s)
      and invs'\<rbrace>
     setThreadState st t
   \<lbrace>\<lambda>rv. invs'\<rbrace>"
  apply (simp add: invs'_def valid_state'_def valid_dom_schedule'_def)
  apply (rule hoare_pre)
   apply (wp valid_irq_node_lift sts_sch_act' sts_valid_queues
             setThreadState_ct_not_inQ)
  apply clarsimp
  apply (rule conjI)
   apply fastforce
  apply (rule conjI)
   apply (clarsimp simp: pred_tcb_at'_def)
   apply (drule obj_at_valid_objs')
    apply (clarsimp simp: valid_pspace'_def)
   apply (clarsimp simp: valid_obj'_def valid_tcb'_def projectKOs)
  sorry (*
   subgoal by (cases st, auto simp: valid_tcb_state'_def
                        split: Structures_H.thread_state.splits)[1]
  apply (rule conjI)
   apply (clarsimp dest!: st_tcb_at_state_refs_ofD'
                   elim!: rsubst[where P=sym_refs]
                  intro!: ext)
  apply (clarsimp elim!: st_tcb_ex_cap'')
  done *)

lemma hf_invs' [wp]:
  "\<lbrace>invs' and sch_act_not t
          and (\<lambda>s. \<forall>p. t \<notin> set(ksReadyQueues s p))
          and st_tcb_at' simple' t
          and ex_nonz_cap_to' t and (\<lambda>s. t \<noteq> ksIdleThread s)\<rbrace>
   handleFault t f \<lbrace>\<lambda>r. invs'\<rbrace>"
  apply (simp add: handleFault_def handleNoFaultHandler_def)
  apply wp
  sorry (*
   apply (simp)
   apply (wp sts_invs_minor'' dmo_invs')+
  apply (rule hoare_post_impErr, rule sfi_invs_plus',
         simp_all)
  apply (strengthen no_refs_simple_strg')
  apply clarsimp
  done *)

declare zipWithM_x_mapM [simp del]

lemma gts_st_tcb':
  "\<lbrace>\<top>\<rbrace> getThreadState t \<lbrace>\<lambda>r. st_tcb_at' (\<lambda>st. st = r) t\<rbrace>"
  apply (rule hoare_strengthen_post)
  apply (rule gts_sp')
  apply simp
  done

lemma si_blk_makes_simple':
  "\<lbrace>st_tcb_at' simple' t and K (t \<noteq> t')\<rbrace>
     sendIPC True call bdg cg cgr cd t' ep
   \<lbrace>\<lambda>rv. st_tcb_at' simple' t\<rbrace>"
  apply (simp add: sendIPC_def)
  apply (rule hoare_seq_ext [OF _ get_ep_inv'])
  sorry (*
  apply (case_tac xa, simp_all)
    apply (rename_tac list)
    apply (case_tac list, simp_all add: case_bool_If case_option_If
                             split del: if_split cong: if_cong)
    apply (rule hoare_pre)
     apply (wp sts_st_tcb_at'_cases setupCallerCap_pred_tcb_unchanged
               hoare_drop_imps)
    apply (clarsimp simp: pred_tcb_at' del: disjCI)
   apply (wp sts_st_tcb_at'_cases)
   apply clarsimp
  apply (wp sts_st_tcb_at'_cases)
  apply clarsimp
  done *)

lemma si_blk_makes_runnable':
  "\<lbrace>st_tcb_at' runnable' t and K (t \<noteq> t')\<rbrace>
     sendIPC True call bdg cg cgr cd t' ep
   \<lbrace>\<lambda>rv. st_tcb_at' runnable' t\<rbrace>"
  apply (simp add: sendIPC_def)
  apply (rule hoare_seq_ext [OF _ get_ep_inv'])
  sorry (*
  apply (case_tac xa, simp_all)
    apply (rename_tac list)
    apply (case_tac list, simp_all add: case_bool_If case_option_If
                             split del: if_split cong: if_cong)
    apply (rule hoare_pre)
     apply (wp sts_st_tcb_at'_cases setupCallerCap_pred_tcb_unchanged
               hoare_vcg_const_imp_lift hoare_drop_imps
              | simp)+
    apply (clarsimp del: disjCI simp: pred_tcb_at' elim!: pred_tcb'_weakenE)
   apply (wp sts_st_tcb_at'_cases)
   apply clarsimp
  apply (wp sts_st_tcb_at'_cases)
  apply clarsimp
  done *)

crunches possibleSwitchTo, completeSignal
  for pred_tcb_at'[wp]: "pred_tcb_at' proj P t"

end

end

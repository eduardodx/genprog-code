(* Main for the predicate project. Process command line and
 * does the appropriate workflow in terms of calling different
 * functions from elsewhere. As, you know, main usually does. *)

open List
open Globals (* global and utility functions *)
open File_process (* file input/output *)
open Predicate (* predicate table maniuplation and predicate ranking *)
open Prune (* pruning/filtering functions *)


(* We can prune the predicates and counters emitted by the sampler in several
 * ways. These heuristics are set by the -filter flag. The -filter flag
 * is one integer; you give it the sum of all the filters you want.
 * 
 * filter bits:
 * 1 - elimination by universal falsehood
 * 2 - elimination by lack of failing coverage
 * 4- elimination by lack of failing example
 * 8 - elimination when increase <= 0
 * 16 - only emit predicates that are sometimes > 0 on successful runs
 *      and always 0 on failing runs
 * 32 - only emit predicates that are always > 0 on all runs
 * 64 - emit predicates that are always 0 on successful runs and 
 *      sometimes > 0 on failing runs
 * 
 *)

let output_baseline ranked_preds pred_tbl exploded_tbl = begin
  let sliced = 
    List.map 
      (fun ((pred_num,pred_counter), importance,
	    increase, context, _,_,_,_,_,_) ->
	 ((pred_num,pred_counter), importance,increase,context))
      ranked_preds in

  let get_pred_set filter_fun =
    let just_pair ((pred_set,pred_counter),_,_,_) = 
      (pred_set,pred_counter) in
    let rec inner_get lst accum_set =
      match lst with
	  ele :: eles -> 
	    if filter_fun ele then
	      inner_get eles 
		(PredSet.add (just_pair ele) accum_set)
	    else
	      inner_get eles accum_set
	| [] -> accum_set 
    in
      inner_get sliced PredSet.empty
  in
    
  let fout = open_out_bin !baseline_out in 

  let preds_imp_gt_zero = 
    get_pred_set (fun ((pred_set, pred_counter), importance, _,_) ->
		    importance > 0.0) in
    
  let preds_inc_gt_zero = 
    get_pred_set (fun ((pred_set,pred_counter), _,increase,_) ->
		    increase > 0.0) in
  let preds_cont_gt_zero = 
    get_pred_set (fun ((pred_set,pred_counter),_,_,context) ->
		    context > 0.0) in
    
  let fltr = fun x -> true in (* make a trivial filter so that 
			       * the pruning functions actually
			       * prune *)
    
  let filtered_by_uf = ref PredSet.empty in
  let filtered_by_lfc = ref PredSet.empty in
  let filtered_by_lfe = ref PredSet.empty in
    
    Hashtbl.iter 
      (fun key ->
	 fun result_list ->
	   if (uf fltr result_list) then begin
	     filtered_by_uf := PredSet.add key !filtered_by_uf
	   end;
	   if (lfe fltr result_list) then begin
	     filtered_by_lfe := PredSet.add key !filtered_by_lfe
	   end
      ) exploded_tbl;
    
    Hashtbl.iter
      (fun site ->
	 fun res_list ->
	   if (lfc fltr res_list) then begin
	     filtered_by_lfe := PredSet.add (site,0) !filtered_by_lfe;
	     filtered_by_lfe := PredSet.add (site,1) !filtered_by_lfe
	   end
      ) pred_tbl;
    
    Marshal.to_channel fout
      ([preds_imp_gt_zero;
	preds_inc_gt_zero;
	preds_cont_gt_zero;
	!filtered_by_uf;
	!filtered_by_lfc;
	!filtered_by_lfe]) [];
    close_out fout
	
(*	let at_pos_at_neg = (atat fltr strip_list) in
	let at_pos_st_neg = (atst fltr strip_list) in 
	let at_pos_nt_neg = (atnt fltr strip_list) in

	let st_pos_at_neg = (stat fltr strip_list) in
	let st_pos_st_neg = (stst fltr strip_list) in
	let st_pos_nt_neg = (stnt fltr strip_list) in

	let nt_pos_at_neg = (ntat fltr strip_list) in
	let nt_pos_st_neg = (ntst fltr strip_list) in*)
(* <--- I don't know if that stuff makes sense right now so
 *      I'll comment it out until I get the other stuff working
 *)

      (* ntnt is covered by previous cases *)

(*	let pred_ranks = [] in do we want to track the actual ranks of
 *      predicates? *)
end
   
let output_rank ranked_preds = begin
  Printf.printf "%d ranked preds\n" (List.length ranked_preds); flush stdout;
  if not !modify_input then begin
    Printf.printf "Predicate,file name,lineno,F(P),S(P),Failure(P),Context,Increase,F(P Observed),S(P Observed),numF,Importance\n";
  end;
  List.iter (fun ((pred_num, pred_counter), 
		  importance, increase, context,
		  fP, sP, failureP, fObserved, sObserved, numF) ->
	       Printf.printf "Pred_num: %d pred_counter: %d " pred_num pred_counter;
	       let (name, filename, lineno) = get_pred_text pred_num pred_counter in 
		 Printf.printf "%s,%s,%s,%g,%g,%g,%g,%g,%g,%g,%g,%g\n" 
		   name filename lineno fP sP failureP context increase fObserved sObserved numF importance;
		 flush stdout)
    ranked_preds
end

let main () = begin
  let compressed = ref true in
  let rank = ref true in

  let runs_in = ref "" in

  let hashes_in = ref "" in 
  let concise_runs_in = ref [] in
  let cbi_hash_tables = ref "" in
    
  let filters = ref 0 in

  let usageMsg = "Process samples produced by Liblit's CBI sampler.\n" in
  let argDescr = [
    "-gen-baseline", Arg.Set_string baseline_out, 
    "\t Generate information from baseline run information, print to X. \
        Doesn't print rank info.";
    (* baseline_out exists to get baseline statistics for a run of a 
     * "broken" program. We will use this baseline info to compare to
     * a variant to get a whole bunch of potential fitness functions *)
    "-uncomp", Arg.Clear compressed, 
              "\t The input files are uncompressed. false by default." ;
    "-no-rank", Arg.Clear rank,
    "\t skip ranking, just produce concise run info." ;
    "-cbi-hin", Arg.Set_string cbi_hash_tables, 
    "\t File containing serialized hash tables from my implementation \
                of CBI." ;
    "-rs", Arg.Set_string runs_in,
            "\t File listing names of files containing runs, followed by a GOOD \
                or BAD on the same line to delineate runs. Files are output of  \
                resolvedSamples output by default. See \"ss\"." ;
    "-cout", Arg.Set_string concise_runs_out, 
            "\t File to print out concise run info.";
    "-hout", Arg.Set_string hashes_out, 
             "\t File to serialize the hash tables.";
    "-cin", Arg.String (fun s -> concise_runs_in := s:: !concise_runs_in),
            "\t File to read in concise good run info. \
	    Requires -hin flag to be set.";
    "-hin", Arg.Set_string hashes_in, 
            "\t File to read serialized hash tables from. \
	     Required if reading in concise run info.";
    "-filter", Arg.Set_int filters, 
            "\t Integer denoting which filtering schemes to apply.";
    "-mi", Arg.Set modify_input, 
            "\t Output formatted to be read into modify.";
    "-debug", Arg.Set debug, "\t Debug printouts.";
  ] 
  in
  let process = ref [] in
  let handleArg a = process := !process @ [a] in
    Arg.parse argDescr handleArg usageMsg ; 
    if not (!hashes_in = "") then begin
      let in_channel = open_in_bin !hashes_in in
	run_num_to_fname_and_good := Marshal.from_channel in_channel;
	close_in in_channel
    end ;

    if not (!cbi_hash_tables == "") then begin
      let in_channel = open_in !cbi_hash_tables in
	site_ht := Marshal.from_channel in_channel;
	let max = 
	  Hashtbl.fold
	  (fun k ->
	     fun v ->
	       fun accum ->
		 if k > accum then k else accum) !site_ht 0 in
	Printf.printf "Largest site num: %d\n" max; flush stdout
    end;
    if not (!runs_in = "") then begin
      Printf.printf "runs: %s\n" !runs_in; flush stdout;
      let file_list = ref [] in
      let fin = open_in !runs_in in 
	try
	  while true do
	    let line = input_line fin in
	    let split = Str.split whitespace_regexp line in
	      file_list := ((hd split), (hd (tl split))) :: !file_list
	  done
	with _ -> close_in fin;
	  let conciseify = 
	    if !compressed then conciseify_compressed_file 
	    else compress_and_conciseify 
	  in
	    
	List.iter (fun (file, gorb) -> conciseify file gorb) !file_list;

	(* print concise runs to concise_run_out *) 
	let out_runs_file = open_out !concise_runs_out in
	  List.iter 
	    (fun (file, _) -> print_run out_runs_file file) 
	    !file_list;
	  close_out out_runs_file;

	  (* serialize out the hashtables so we can interpret the printed data 
	   * again later *)
	  let fout = open_out_bin !hashes_out in
	    Marshal.to_channel fout (!run_num_to_fname_and_good) [];
	    close_out fout;
	    print "post hashtable print\n";
    end;        
    (* we read in any concise output generated by print_run; this is
     * less efficient then just serializing the hashtable containing
     * runs to a file, but allows for human-readable output, which
     * for now is a win *)

    if (not (empty !concise_runs_in)) then
      List.iter (fun file -> read_run file) !concise_runs_in;

    (* OK. Now, under all circumstances, we have all of our runs into the 3 
     * hash tables. Now, process predicates *)
    let pred_tbl : (int, int list list) Hashtbl.t = make_pred_tbl () in

    let filter_bit_set bit = (!filters land bit) == bit in

    let pred_pruned =
      if (filter_bit_set 2) then 
        prune_on_full_set pred_tbl filter_bit_set 
      else pred_tbl in
    let exploded_tbl = explode_preds pred_pruned in 
    let counter_pruned = prune_on_individual_counters exploded_tbl filter_bit_set in
    let increase_pruned = if (filter_bit_set 8) then 
                           prune_on_increase counter_pruned 
                          else counter_pruned 
    in
    let ranked_preds = rank_preds increase_pruned in

      if !baseline_out <> "" then begin 
	rank := false;
	output_baseline ranked_preds pred_tbl exploded_tbl
      end;
      if !rank then output_rank ranked_preds
end ;;

main () ;;

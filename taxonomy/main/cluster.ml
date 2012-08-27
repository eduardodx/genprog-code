open Batteries
open Set
open Map
open Random
open Utils
open Globals
open Datapoint
open Diffs
(*open Distance
open Tprint
open Template*)

let cluster = ref false 
let k = ref 2

let load_clusters = ref ""
let save_clusters = ref ""
let _ =
  options := !options @
    [
      "--loadc", Arg.Set_string load_clusters, "\t load saved cluster cache from X\n";
      "--savec", Arg.Set_string save_clusters, "\t save cluster cache to X\n"; 
]

module type KClusters =
sig
  type configuration

  type pointSet
  type pointMap
  type cluster
  type clusters 

  val print_configuration : configuration -> unit

  val init : unit -> unit
  val save : unit -> unit
  val cost : configuration -> float
  val random_config : int -> pointSet -> configuration
  val compute_clusters : configuration -> pointSet -> clusters * float
  val kmedoid : int -> pointSet -> configuration
end

module KClusters =
  functor (DP : DataPoint ) ->
struct

  type pointSet = DP.t Set.t
  type pointMap = (DP.t, pointSet) Map.t

  type cluster = pointSet
  type clusters = pointMap 

  (*
   * 1. Initialize: randomly select k of the n data points as the
   * medoids
   * 2. Associate each data point to the closest medoid. ("closest"
   * here is defined using any valid distance metric, most commonly
   * Euclidean distance, Manhattan distance or Minkowski distance) 
   * 3. For each medoid m
   *      1. For each non-medoid data point o
   *          1. Swap m and o and compute the total cost of the configuration
   * 4. Select the configuration with the lowest cost.
   * 5. repeat steps 2 to 5 until there is no change in the medoid.
   *)

  type configuration = pointSet


  (* debug printout functions *)
  let print_configuration config =
	let num = ref 0 in
	Set.iter (fun p -> pprintf "Medoid %d: " !num; incr num; let str = DP.to_string p in pprintf "%s\n" str) config

  let print_cluster cluster medoid medoids = 
	Set.iter (fun point -> 
	  let str = DP.to_string point in
		let distance = DP.distance medoid point in 
		  pprintf "\n\nPoint: %s," str;
		  DP.more_info medoid point; 
		  pprintf " Distance from medoid: %g\n" distance;
          pprintf " Distance from other medoids: ";
            Set.iter (fun p -> if p <> medoid then pprintf "%g, " (DP.distance point p)) medoids;
            pprintf "\n";
		  flush stdout) cluster

  let print_clusters clusters medoids =
	let num = ref 0 in
	Map.iter
	  (fun medoid cluster ->
		pprintf "Cluster %d:\n" (Ref.post_incr num);
        pprintf "count: %d\n" (Set.cardinal cluster);
		let medoidstr = DP.to_string medoid in 
		  pprintf "medoid: %s\n" medoidstr;
		  print_cluster cluster medoid medoids;
		  pprintf "\n"; flush stdout) clusters

  let clusters_cache : (pointSet, (clusters * float)) Hashtbl.t = hcreate 100

  let init () = 
    if !load_clusters <> "" then begin
      let fin = open_in_bin !load_clusters in 
      let ht = Marshal.input fin in
        hiter (fun k v -> hadd clusters_cache k v) ht;
        close_in fin 
    end

  let save () = () (* FIXME *)
(*    if !save_clusters <> "" then begin
      let fout = open_out_bin !save_clusters in 
        Marshal.output fout clusters_cache;
        close_out fout
    end
*)
  let random_config (k : int) (data : pointSet) : configuration =
	let data_enum = Set.enum data in
	let firstk = Enum.take k data_enum in
	let set = Set.of_enum firstk in
	  set
(* takes a configuration (a set of medoids) and a set of data and
  computes a list of k clusters, where k is the length of the medoid
  set/configuraton.  A data point is in a cluster if its distance from
  the cluster's medoid is less than its distance from any other
  medoid. *)

  let compute_clusters (medoids : configuration) (data : pointSet) : clusters * float =
    ht_find clusters_cache medoids
      (fun _ ->
	    let init_map = 
	      Set.fold
		    (fun medoid clusters ->
		      Map.add medoid (Set.empty) clusters) medoids (Map.empty) in
        let data = Set.filter (fun dp -> not (Set.mem dp medoids)) data in
	      Set.fold
	        (fun point (clusters,cost) -> 
		      let (distance,medoid,_) =
			    Set.fold
			      (fun medoid (bestdistance,bestmedoid,is_default) ->
				    let distance = DP.distance point medoid in
				      if distance < bestdistance || is_default
				      then (distance,medoid,false)
			          else (bestdistance,bestmedoid,is_default)
			      ) medoids (0.0,DP.default,true)
		      in
		      let cluster = Map.find medoid clusters in
		      let cluster' = Set.add point cluster in
			    (Map.add medoid cluster' clusters),(distance +. cost)
	        ) data (init_map,0.0))

  let new_config (config : configuration) (medoid : DP.t) (point : DP.t) : configuration =
	let config' = Set.remove medoid config in
	let config'' = Set.add point config' in
	  config''

  let kmedoid ?(savestate=(false,"")) (k : int) (data : pointSet) : configuration = 
(*    debug "number in set: %d\n" (Set.cardinal data);*)
(*    debug "data:\n";
    Set.iter (fun point -> debug "%s\n" (DP.to_string point)) data;
    debug "done printing data, clustering\n";*)
	let init_config : configuration = random_config k data in
	let clusters,cost = compute_clusters init_config data in
(*    let count = ref 0 in*)
    let rec compute_config config clusters cost data =
(*      debug "pass: %d\n" (Ref.post_incr count);*)
      DP.save ();
      let data' = Set.diff data config in
      let best_config,best_clusters,cost' = 
        Set.fold
          (fun medoid (best_config,best_clusters,cost) ->
            Set.fold
              (fun point (best_config,best_clusters,cost) ->
                assert(point <> medoid);
                let config' = new_config config medoid point in
                  assert((Set.cardinal config') = (Set.cardinal config));
                  if hmem clusters_cache config' then best_config,best_clusters,cost
                  else begin
                    let clusters',cost' = compute_clusters config' data in
                      if cost' < cost then 
                        config',clusters',cost'
                      else 
                        best_config,best_clusters,cost
                  end
              ) data' (best_config,best_clusters,cost)
          ) config (config,clusters,cost)
      in
        if (Set.cardinal (Set.diff best_config config)) = 0 then config,clusters,cost 
        else compute_config best_config best_clusters cost' data
    in
    let config,clusters,cost = compute_config init_config clusters cost data in
	  pprintf "  Clusters: \n";
	  print_clusters clusters config;
	  pprintf "cost is: %g\n" cost; flush stdout;
	  config
end


module TestCluster = KClusters(XYPoint)
module ChangeCluster = KClusters(ChangePoint)

let test_cluster clusterme =
  let points = 
    emap
      (fun str ->
        let split = Str.split comma_regexp str in
        let x = List.hd split in 
          {XYPoint.x = int_of_string x; XYPoint.y = int_of_string (List.hd (List.tl split))}
      )
      (File.lines_of clusterme) in
    TestCluster.kmedoid !k (Set.of_enum points)
    

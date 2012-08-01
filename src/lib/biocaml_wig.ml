open Biocaml_internal_pervasives
open Tuple

type comment = [
| `comment of string
]
type variable_step = [
| `variable_step_state_change of string * int option (* name x span *)
| `variable_step_value of int * float
]
type fixed_step = [
| `fixed_step_state_change of string * int * int * int option
(* name, start, step, span *)
| `fixed_step_value of float
]  
type bed_graph_value = string * int * int * float
  
type t = [comment | variable_step | fixed_step | `bed_graph_value of bed_graph_value ]


type parse_error = [
| `cannot_parse_key_values of Biocaml_pos.t * string
| `empty_line of Biocaml_pos.t
| `incomplete_line of Biocaml_pos.t * string
| `missing_chrom_value of Biocaml_pos.t * string
| `missing_start_value of Biocaml_pos.t * string
| `missing_step_value of Biocaml_pos.t * string
| `wrong_start_value of Biocaml_pos.t * string
| `wrong_step_value of Biocaml_pos.t * string
| `unrecognizable_line of Biocaml_pos.t * string list
| `wrong_bed_graph_value of Biocaml_pos.t * string
| `wrong_fixed_step_value of Biocaml_pos.t * string
| `wrong_span_value of Biocaml_pos.t * string
| `wrong_variable_step_value of Biocaml_pos.t * string
]
let parse_error_to_string =
  let pos () a = Biocaml_pos.to_string a in
  function
  | `cannot_parse_key_values (p, s) ->
    sprintf "cannot_parse_key_values (%a, %S)" pos p s
  | `empty_line p -> sprintf "empty_line (%a)" pos p
  | `incomplete_line (p, v) -> (* Biocaml_pos.t * string *)
    sprintf "incomplete_line (%a, %s)" pos p v
  | `missing_chrom_value (p, v) -> (* Biocaml_pos.t * string *)
    sprintf "missing_chrom_value (%a, %s)" pos p v
  | `missing_start_value (p, v) -> (* Biocaml_pos.t * string *)
    sprintf "missing_start_value (%a, %s)" pos p v
  | `missing_step_value (p, v) -> (* Biocaml_pos.t * string *)
    sprintf "missing_step_value (%a, %s)" pos p v
  | `wrong_start_value (p, v) -> (* Biocaml_pos.t * string *)
    sprintf "wrong_start_value (%a, %s)" pos p v
  | `wrong_step_value (p, v) -> (* Biocaml_pos.t * string *)
    sprintf "wrong_step_value (%a, %s)" pos p v
  | `unrecognizable_line (p, v) -> (* Biocaml_pos.t * string list *)
    sprintf "unrecognizable_line (%a, %s)" pos p (String.concat ~sep:" " v)
  | `wrong_bed_graph_value (p, v) -> (* Biocaml_pos.t * string *)
    sprintf "wrong_bed_graph_value (%a, %s)" pos p v
  | `wrong_fixed_step_value (p, v) -> (* Biocaml_pos.t * string *)
    sprintf "wrong_fixed_step_value (%a, %s)" pos p v
  | `wrong_span_value (p, v) -> (* Biocaml_pos.t * string *)
    sprintf "wrong_span_value (%a, %s)" pos p v
  | `wrong_variable_step_value (p, v) -> (* Biocaml_pos.t * string *)
    sprintf "wrong_variable_step_value (%a, %s)" pos p v

      
let explode_key_value loc s =
  try
    let by_space =
      String.split_on_chars s ~on:[' '; '\n'; '\t'; '\r']
      |! List.filter ~f:((<>) "") in
    Ok (List.map by_space (fun s ->
      begin match String.split ~on:'=' s with
      | [ key; value ] -> (key, value)
      | anyother -> raise Not_found
      end))
  with
    Not_found -> Error (`cannot_parse_key_values (loc, s))
      
let rec next ?(pedantic=true) ?(sharp_comments=true) p =
  let open Biocaml_transform.Line_oriented in
  let open Result in
  let assoc_find ~missing l v =
    match List.Assoc.find l v with | Some v -> Ok v | None -> Error missing in
  let assoc_find_map ~missing ~wrong ~f l v =
    match List.Assoc.find l v with
    | Some v -> (try Ok (f v) with e -> Error wrong)
    | None -> Error missing in
  let output_result = function  Ok o -> `output o | Error e -> `error e in
  match next_line p with
  | Some "" ->
    if pedantic then `error (`empty_line (current_position p)) else `not_ready
  | Some l when sharp_comments && String.is_prefix l ~prefix:"#" ->
    `output (`comment String.(sub l ~pos:1 ~len:(length l - 1)))
  | Some l when String.is_prefix l ~prefix:"fixedStep" ->
    let output_m =
      explode_key_value (current_position p)
        String.(chop_prefix_exn l ~prefix:"fixedStep")
      >>= fun assoc ->
      assoc_find assoc "chrom" ~missing:(`missing_chrom_value (current_position p, l))
      >>= fun chrom ->
      assoc_find_map assoc "start" 
        ~missing:(`missing_start_value (current_position p, l))
        ~f:Int.of_string ~wrong:(`wrong_start_value (current_position p, l))
      >>= fun start ->
      assoc_find_map assoc "step" 
        ~missing:(`missing_step_value (current_position p, l))
        ~f:Int.of_string ~wrong:(`wrong_step_value (current_position p, l))
      >>= fun step ->
      begin match List.Assoc.find assoc "span" with
      | None ->
        Ok (`fixed_step_state_change (chrom, start, step, None))
      | Some span ->
        begin match Option.try_with (fun () -> Int.of_string span) with
        | Some i ->
          Ok (`fixed_step_state_change (chrom, start, step, Some i))
        | None -> Error (`wrong_span_value (current_position p, span))
        end
      end
    in
    output_result output_m
  | Some l when String.is_prefix l ~prefix:"variableStep" ->
    let output_m =
      explode_key_value (current_position p)
        String.(chop_prefix_exn l ~prefix:"variableStep")
      >>= fun assoc ->
      assoc_find assoc "chrom" ~missing:(`missing_chrom_value (current_position p, l))
      >>= fun chrom ->
      begin match List.Assoc.find assoc "span" with
      | None -> return (`variable_step_state_change (chrom, None))
      | Some span ->
        begin match Option.try_with (fun () -> Int.of_string span) with
        | Some i -> return (`variable_step_state_change (chrom, Some i))
        | None -> fail (`wrong_span_value (current_position p, span))
        end
      end
    in
    output_result output_m
  | Some l ->
    let by_space =
      String.split_on_chars l ~on:[' '; '\n'; '\t'; '\r']
      |! List.filter ~f:((<>) "") in
    begin match by_space with
    | [ one_value ] ->
      (try `output (`fixed_step_value Float.(of_string one_value))
       with e -> `error (`wrong_fixed_step_value (current_position p, l)))
    | [ fst_val; snd_val] ->
      (try `output (`variable_step_value (Int.of_string fst_val,
                                          Float.of_string snd_val))
       with e -> `error (`wrong_variable_step_value (current_position p, l)))
    | [ chr; b; e; v; ] ->
      (try `output (`bed_graph_value (chr,
                                      Int.of_string b,
                                      Int.of_string e,
                                      Float.of_string v))
       with e -> `error (`wrong_bed_graph_value (current_position p, l)))
    | l ->
      `error (`unrecognizable_line (current_position p, l))
    end
  | None -> 
    `not_ready
        
        
let parser ?filename ?pedantic ?sharp_comments () =
  let name = sprintf "wig_parser:%s" Option.(value ~default:"<>" filename) in
  let module LOP =  Biocaml_transform.Line_oriented  in
  let lo_parser = LOP.parser ?filename () in
  Biocaml_transform.make_stoppable ~name ()
    ~feed:(LOP.feed_string lo_parser)
    ~next:(fun stopped ->
      match next ?pedantic ?sharp_comments lo_parser with
      | `output r -> `output r
      | `error e -> `error e
      | `not_ready ->
        if stopped then (
          match LOP.finish lo_parser with
          | `ok -> `end_of_stream
          | `error ([], Some kind_of_line) ->
            `error (`incomplete_line (LOP.current_position lo_parser, kind_of_line))
          | `error (l, o) ->
            failwithf "incomplete wig input? %S %S"
              (String.concat ~sep:"<RET>" l) Option.(value ~default:"" o) ()
        ) else
          `not_ready)


let printer () =
  let module PQ = Biocaml_transform.Printer_queue in
  let printer =
    PQ.make ~to_string:(function
    | `comment c -> sprintf "#%s\n" c
    | `variable_step_state_change (chrom, span) ->
      sprintf "variableStep chrom=%s%s\n" chrom
        Option.(value_map ~default:"" span ~f:(sprintf " span=%d"))
    | `variable_step_value (pos, v) -> sprintf "%d %g\n" pos v
    | `fixed_step_state_change (chrom, start, step, span) ->
      sprintf "fixedStep chrom=%s start=%d step=%d%s\n" chrom start step 
        Option.(value_map ~default:"" span ~f:(sprintf " span=%d"))
    | `fixed_step_value v -> sprintf "%g\n" v
    | `bed_graph_value (chrom, start, stop, v) ->
      sprintf "%s %d %d %g\n" chrom start stop v) () in
  Biocaml_transform.make_stoppable ~name:"wig_printer" ()
    ~feed:(fun r -> PQ.feed printer r)
    ~next:(fun stopped ->
      match (PQ.flush printer) with
      | "" -> if stopped then `end_of_stream else `not_ready
      | s -> `output s)


let to_bed_graph () =
  let queue = Queue.create () in
  let current_state = ref None in
  Biocaml_transform.make_stoppable ~name:"wig_to_variable_step" ()
    ~feed:(function
    | `comment _ -> ()
    | `bed_graph_value already_done ->
      Queue.enqueue queue (`output already_done)
    | `variable_step_state_change (chrom, span) ->
      current_state := Some (`variable (chrom, span))
    | `variable_step_value (pos, v) ->
      begin match !current_state with
      | Some (`variable (chrom, span)) ->
        let stop = pos + Option.(value ~default:1 span) - 1 in
        Queue.enqueue queue (`output  (chrom, pos, stop, v))
      | other ->
        Queue.enqueue queue (`error (`not_in_variable_step_state))
      end
    | `fixed_step_state_change (chrom, start, step, span) ->
      current_state := Some (`fixed (chrom, start, step , span, 0))
    | `fixed_step_value v ->
      begin match !current_state with
      | Some (`fixed (chrom, start, step, span, current)) ->
        let pos = start + (step * current) in
        let stop = pos + Option.(value ~default:1 span) - 1 in
        Queue.enqueue queue (`output (chrom, pos, stop, v));
        current_state := Some  (`fixed (chrom, start, step , span, current + 1))
      | other ->
        Queue.enqueue queue (`error (`not_in_fixed_step_state))
      end)
    ~next:(fun stopped ->
      match Queue.dequeue queue with
      | None -> if stopped then `end_of_stream else `not_ready
      | Some v -> v)
  



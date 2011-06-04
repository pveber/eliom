(* Ocsigen
 * http://www.ocsigen.org
 * Copyright (C) 2010 Vincent Balat
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, with linking exception;
 * either version 2.1 of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
 *)

open Eliom_pervasives

(* == Closure *)

let closure_table  : (int64, poly -> unit) Hashtbl.t = Hashtbl.create 0
let register_closure id (f : 'a -> unit) =
  Hashtbl.add closure_table id (Obj.magic f : poly -> unit)
let find_closure = Hashtbl.find closure_table

(* == Process nodes (a.k.a. nodes with a unique Dom instance on each client) *)

let (register_node, find_node) =
  let process_nodes : (string, Dom.node Js.t) Hashtbl.t = Hashtbl.create 0 in
  let find id =
    let node = Hashtbl.find process_nodes id in
    if String.lowercase (Js.to_string node##nodeName) = "script" then
      (* We don't wan't to reexecute "unique" script... *)
      (Dom_html.document##createTextNode (Js.string "") :> Dom.node Js.t)
    else
      node
  in
  let register id node = Hashtbl.add process_nodes id node in
  (register, find)

(* == Event *)

(* forward declaration... *)
let change_page_uri_ = ref (fun ?cookies_info href -> assert false)
let change_page_get_form_ = ref (fun ?cookies_info form href -> assert false)
let change_page_post_form_ = ref (fun ?cookies_info form href -> assert false)

let reify_caml_event node ce = match ce with
  | XML.CE_call_service (`A, cookies_info) ->
      (fun () ->
	let href = (Js.Unsafe.coerce node : Dom_html.anchorElement Js.t)##href in
	!change_page_uri_ ?cookies_info (Js.to_string href); false)
  | XML.CE_call_service (`Form_get, cookies_info) ->
      (fun () ->
	let form = (Js.Unsafe.coerce node : Dom_html.formElement Js.t) in
	let action = Js.to_string form##action in
	!change_page_get_form_ ?cookies_info form action; false)
  | XML.CE_call_service (`Form_post, cookies_info) ->
      (fun () ->
	let form = (Js.Unsafe.coerce node : Dom_html.formElement Js.t) in
	let action = Js.to_string form##action in
	!change_page_post_form_ ?cookies_info form action; false)
  | XML.CE_client_closure f ->
    (fun () -> try f (); true with False -> false)
  | XML.CE_registered_closure (id, args) ->
      try
	let f = find_closure id in
	(fun () -> try f args; true with False -> false)
      with Not_found ->
	Firebug.console##error(Printf.sprintf "Closure not found (%Ld)" id);
	(fun () -> false)

let reify_event node ev = match ev with
  | XML.Raw ev -> Js.Unsafe.variable ev
  | XML.Caml ce -> reify_caml_event node ce

let register_event_handler node (name, ev) =
  let f = reify_caml_event node ev in
  assert(String.sub name 0 2 = "on");
  Js.Unsafe.set node (Js.string name)
    (Dom_html.handler (fun _ -> Js.bool (f ())))

(* == Register nodes id and event in the orginal Dom. *)

let rec relink_dom node (id, attribs, childrens_ref_tree) =
  List.iter
    (register_event_handler (Js.Unsafe.coerce node : Dom_html.element Js.t))
    attribs;
  begin match id with
  | None -> ()
  | Some id ->
      try
	let pnode = find_node id in
	let parent = Js.Opt.get (node##parentNode) (fun _ -> assert false) in
	Dom.replaceChild parent pnode node
      with Not_found ->
	register_node id node
  end;
  let childrens =
    List.filter
      (fun node -> node##nodeType = Dom.ELEMENT)
      (Dom.list_of_nodeList (node##childNodes)) in
  relink_dom_list childrens childrens_ref_tree

and relink_dom_list nodes ref_trees =
  match nodes, ref_trees with
  | node :: nodes, XML.Ref_node ref_tree :: ref_trees ->
      relink_dom node ref_tree;
      relink_dom_list nodes ref_trees
  | nodes, XML.Ref_empty i :: ref_trees ->
      relink_dom_list (List.chop i nodes) ref_trees
  | _, [] -> ()
  | [], _ ->
    Firebug.console##error(Js.string "Incorrect sparse tree.")

(* == Convertion from OCaml XML.elt nodes to native JavaScript Dom nodes *)

module Html5 = struct

  let rebuild_attrib node a = match a with
    | XML.AFloat (name, f) -> Js.Unsafe.set node (Js.string name) (Js.Unsafe.inject f)
    | XML.AInt (name, i) -> Js.Unsafe.set node (Js.string name) (Js.Unsafe.inject i)
    | XML.AStr (name, s) -> Js.Unsafe.set node (Js.string name) (Js.string s)
    | XML.AStrL (XML.Space, name, sl) ->
      Js.Unsafe.set node
	(Js.string name)
	(Js.Unsafe.inject (Js.string
			     (match sl with
			       | [] -> ""
			       | a::l -> List.fold_left (fun r s -> r ^ " " ^ s) a l)))
    | XML.AStrL (XML.Comma, name, sl) ->
      Js.Unsafe.set node
	(Js.string name)
	(Js.Unsafe.inject (Js.string
			     (match sl with
			       | [] -> ""
			       | a::l -> List.fold_left (fun r s -> r ^ "," ^ s) a l)))

  let rebuild_rattrib node ra = match XML.racontent ra with
    | XML.RA a -> rebuild_attrib node a
    | XML.RACamlEvent ev -> register_event_handler node ev

  let rec rebuild_node elt =
    match XML.get_unique_id elt with
      | None -> raw_rebuild_node (XML.content elt)
      | Some id ->
	  try (find_node id :> Dom.node Js.t)
	  with Not_found ->
	  let node = raw_rebuild_node (XML.content elt) in
	  register_node id node;
	  node

  and raw_rebuild_node = function
    | XML.Empty
    | XML.Comment _ ->
	(* FIXME *)
	(Dom_html.document##createTextNode (Js.string "") :> Dom.node Js.t)
    | XML.EncodedPCDATA s
    | XML.PCDATA s -> (Dom_html.document##createTextNode (Js.string s) :> Dom.node Js.t)
    | XML.Entity s -> assert false (* FIXME *)
    | XML.Leaf (name,attribs) ->
      let node = Dom_html.document##createElement (Js.string name) in
      List.iter (rebuild_rattrib node) attribs;
      (node :> Dom.node Js.t)
    | XML.Node (name,attribs,childrens) ->
      let node = Dom_html.document##createElement (Js.string name) in
      List.iter (rebuild_rattrib node) attribs;
      List.iter (fun c -> Dom.appendChild node (rebuild_node c)) childrens;
      (node :> Dom.node Js.t)

  let rebuild_node elt = Js.Unsafe.coerce (rebuild_node (HTML5.M.toelt elt))

  let of_element = rebuild_node

  let of_html = rebuild_node
  let of_head = rebuild_node
  let of_link = rebuild_node
  let of_title = rebuild_node
  let of_meta = rebuild_node
  let of_base = rebuild_node
  let of_style = rebuild_node
  let of_body = rebuild_node
  let of_form = rebuild_node
  let of_optGroup = rebuild_node
  let of_option = rebuild_node
  let of_select = rebuild_node
  let of_input = rebuild_node
  let of_textArea = rebuild_node
  let of_button = rebuild_node
  let of_label = rebuild_node
  let of_fieldSet = rebuild_node
  let of_legend = rebuild_node
  let of_uList = rebuild_node
  let of_oList = rebuild_node
  let of_dList = rebuild_node
  let of_li = rebuild_node
  let of_div = rebuild_node
  let of_paragraph = rebuild_node
  let of_heading = rebuild_node
  let of_quote = rebuild_node
  let of_pre = rebuild_node
  let of_br = rebuild_node
  let of_hr = rebuild_node
  let of_anchor = rebuild_node
  let of_image = rebuild_node
  let of_object = rebuild_node
  let of_param = rebuild_node
  let of_area = rebuild_node
  let of_map = rebuild_node
  let of_script = rebuild_node
  let of_tableCell = rebuild_node
  let of_tableRow = rebuild_node
  let of_tableCol = rebuild_node
  let of_tableSection = rebuild_node
  let of_tableCaption = rebuild_node
  let of_table = rebuild_node
  let of_canvas = rebuild_node
  let of_iFrame = rebuild_node

end

let current_fragment = ref ""
let url_fragment_prefix = "!"
let url_fragment_prefix_with_sharp = "#!"

let create_request_
    ?absolute ?absolute_path ?https
    ~(service : ('get, 'post,
                 [< `Attached of (Eliom_services.attached_service_kind, [< Eliom_services.getpost]) Eliom_services.a_s
                 | `Nonattached of [< Eliom_services.getpost] Eliom_services.na_s ],
                 [< Eliom_services.suff ], 'h, 'i,
                 [< Eliom_services.registrable ], 'j)
        Eliom_services.service)
    ?hostname ?port ?fragment ?keep_nl_params ?nl_params ?keep_get_na_params
    g p =
  match Eliom_services.get_get_or_post service with
    | `Get ->
        let uri =
          Eliom_uri.make_string_uri
            ?absolute ?absolute_path ?https
            ~service
            ?hostname ?port ?fragment ?keep_nl_params ?nl_params g
        in
        Left uri
    | `Post ->
        let path, g, fragment, p =
          Eliom_uri.make_post_uri_components
            ?absolute ?absolute_path ?https
            ~service
            ?hostname ?port ?fragment ?keep_nl_params ?nl_params
            ?keep_get_na_params g p
        in
        let uri =
          Eliom_uri.make_string_uri_from_components (path, g, fragment)
        in
        Right (uri, p)



let exit_to
    ?absolute ?absolute_path ?https
    ~(service : ('get, 'post,
                 [< `Attached of (Eliom_services.attached_service_kind, [< Eliom_services.getpost]) Eliom_services.a_s
                 | `Nonattached of [< Eliom_services.getpost] Eliom_services.na_s ],
                 [< Eliom_services.suff ], 'h, 'i,
                 [< Eliom_services.registrable ], 'j)
        Eliom_services.service)
    ?hostname ?port ?fragment ?keep_nl_params ?nl_params ?keep_get_na_params
    g p =
  (match create_request_
     ?absolute ?absolute_path ?https ~service ?hostname ?port ?fragment
     ?keep_nl_params ?nl_params ?keep_get_na_params
     g p
   with
     | Left uri -> Eliom_request.redirect_get uri
     | Right (uri, p) -> Eliom_request.redirect_post uri p)


(** This will change the URL, without doing a request.
    As browsers do not not allow to change the URL,
    we write the new URL in the fragment part of the URL.
    A script must do the redirection if there is something in the fragment.
    Usually this function is only for internal use.
*)
let change_url_string uri =
  current_fragment := url_fragment_prefix_with_sharp^uri;
  Dom_html.window##location##hash <- Js.string (url_fragment_prefix^uri)

let change_url
(*VVV is it safe to have absolute URLs? do we accept non absolute paths? *)
    ?absolute ?absolute_path ?https
    ~(service : ('get, 'post,
                 [< `Attached of (Eliom_services.attached_service_kind, [< Eliom_services.getpost]) Eliom_services.a_s
                 | `Nonattached of [< Eliom_services.getpost] Eliom_services.na_s ],
                 [< Eliom_services.suff ], 'h, 'i,
                 [< Eliom_services.registrable ], 'j)
        Eliom_services.service)
    ?hostname ?port ?fragment ?keep_nl_params ?nl_params ?keep_get_na_params
    g p =
(*VVV only for GET services? *)
  let uri =
    (match create_request_
       ?absolute ?absolute_path ?https
       ~service
       ?hostname ?port ?fragment ?keep_nl_params ?nl_params ?keep_get_na_params
       g p
     with
       | Left uri -> uri
       | Right (uri, p) -> uri)
  in
  change_url_string uri

let on_unload_scripts = ref []
let at_exit_scripts = ref []

(*
let _ =
  Dom_html.window##onbeforeunload <-
    (Dom_html.handler
       (fun ev ->
(* We cannot wait for the lwt thread to finish before exiting ...
*)
         ignore
           ((match !on_unload_script with
             | None -> Lwt.return ()
             | Some script -> Js.Unsafe.variable script) >>= fun () ->
            (match !at_exit_script with
              | None -> Lwt.return ()
              | Some script -> Js.Unsafe.variable script));
         Js.bool true))

(* Also:
  May be we can add automatically a special "close_process" coservice for each
  Eliom site, that will be called by the process when exiting.
*)
*)

(* BEGIN FORMDATA HACK: This is only needed if FormData is not available in the browser.
   When it will be commonly available, remove all sections marked by "FORMDATA HACK" !
   Notice: this hack is used to circumvent a limitation in FF4 implementation of formdata:
     if the user click on a button in a form, formdatas created in the onsubmit callback normaly contains the value of the button. ( it is the behaviour of chromium )
     in FF4, it is not the case: we must do this hack to find wich button was clicked.

   This is implemented in:
   * this file -> here and called in load_eliom_data
   * Eliom_request: in send_post_form
   * in js_of_ocaml, module Form: the code to emulate FormData *)

let onclick_on_body_handler event =
  (match Dom_html.tagged (Dom_html.eventTarget event) with
    | Dom_html.Button button ->
	(Js.Unsafe.variable "window")##eliomLastButton <- Some button;
    | Dom_html.Input input when input##_type = Js.string "submit" ->
	(Js.Unsafe.variable "window")##eliomLastButton <- Some input;
    | _ ->
	(Js.Unsafe.variable "window")##eliomLastButton <- None);
  Js._true

let add_onclick_events () =
  ignore (Dom_html.addEventListener ( Dom_html.window##document##body )
	    Dom_html.Event.click ( Dom_html.handler onclick_on_body_handler )
	    Js._true : Dom_html.event_listener_id);
  true

(* END FORMDATA HACK *)

let load_eliom_data page =
  let js_data = Eliom_unwrap.unwrap (unmarshal_js_var "eliom_data") in
  relink_dom_list
    [(page :> Dom.node Js.t)]
    [js_data.Eliom_types.ejs_ref_tree];
  Eliommod_cookies.update_cookie_table js_data.Eliom_types.ejs_tab_cookies;
  Eliom_request_info.set_session_info js_data.Eliom_types.ejs_sess_info;
  change_url_string js_data.Eliom_types.ejs_url;
  let on_load =
    List.map
      (reify_event Dom_html.document##documentElement)
      js_data.Eliom_types.ejs_onload in
  let on_unload =
    List.map
      (reify_event Dom_html.document##documentElement)
      js_data.Eliom_types.ejs_onunload in
  on_unload_scripts := [fun () -> List.for_all (fun f -> f ())
  on_unload];
  add_onclick_events :: on_load

let on_unload f =
  on_unload_scripts :=
    (fun () -> try f(); true with False -> false) :: !on_unload_scripts

let fake_page = Dom_html.createHtml Dom_html.document

let get_head_body page =
  match Dom.list_of_nodeList fake_page##childNodes with
  | [_; head; body] ->
     (* First node is ocsigen advertisement *)
     (Js.Unsafe.coerce head : Dom_html.headElement Js.t),
     (Js.Unsafe.coerce body : Dom_html.bodyElement Js.t)
  | _ -> assert false

let get_data_script page =
  let head, _ = get_head_body page in
  match Dom.list_of_nodeList head##childNodes with
    | _ :: data_script :: _ ->
      (Js.Unsafe.coerce data_script : Dom_html.scriptElement Js.t)
    | _ -> assert false

let set_content content =
  ignore (List.for_all (fun f -> f ()) !on_unload_scripts);
  on_unload_scripts := [];
  (* Hack to make the result considered as DOM : *)
  fake_page##innerHTML <- Js.string content;
  let data_script = get_data_script fake_page in
  Dom.appendChild (Dom_html.document##head) data_script##cloneNode(Js._true);
  let on_load = load_eliom_data fake_page in
  let head, body = get_head_body fake_page in
  Dom.replaceChild
    (Dom_html.document##documentElement)
    head (Dom_html.document##head);
  Dom.replaceChild
    (Dom_html.document##documentElement)
    body (Dom_html.document##body);
  ignore (List.for_all (fun f -> f ()) on_load);
  Lwt.return ()

let change_page
    ?absolute ?absolute_path ?https ~service ?hostname ?port ?fragment
    ?keep_nl_params ?nl_params ?keep_get_na_params
    get_params post_params =

  if not (Eliom_services.xhr_with_cookies service)
  then
    Lwt.return
      (exit_to
         ?absolute ?absolute_path ?https ~service ?hostname ?port ?fragment
	 ?keep_nl_params ?nl_params ?keep_get_na_params
         get_params post_params)
  else
    lwt r = match
        create_request_
          ?absolute ?absolute_path ?https ~service ?hostname ?port ?fragment
	  ?keep_nl_params ?nl_params ?keep_get_na_params
          get_params post_params
     with
       | Left uri ->
         Eliom_request.http_get
           ?cookies_info:(Eliom_uri.make_cookies_info (https, service)) uri []
       | Right (uri, p) ->
         Eliom_request.http_post
           ?cookies_info:(Eliom_uri.make_cookies_info (https, service)) uri p in
    set_content r

let change_page_uri ?cookies_info ?(get_params = []) uri =
  try_lwt
  lwt r = Eliom_request.http_get ?cookies_info uri get_params in
  set_content r
with e ->
  Firebug.console##debug(Js.string (Printexc.to_string e));
  Lwt.return ()

let change_page_get_form ?cookies_info form uri =
  let form = Js.Unsafe.coerce form in
  lwt r = Eliom_request.send_get_form ?cookies_info form uri in
  set_content r

let change_page_post_form ?cookies_info form uri =
  let form = Js.Unsafe.coerce form in
  lwt r = Eliom_request.send_post_form ?cookies_info form uri in
  set_content r

let _ =
  change_page_uri_ :=
    (fun ?cookies_info href -> ignore(change_page_uri ?cookies_info href));
  change_page_get_form_ :=
    (fun ?cookies_info form href -> ignore(change_page_get_form ?cookies_info form href));
  change_page_post_form_ :=
    (fun ?cookies_info form href -> ignore(change_page_post_form ?cookies_info form href))

let call_service
    ?absolute ?absolute_path ?https
    ~service
    ?hostname ?port ?fragment ?keep_nl_params ?nl_params ?keep_get_na_params
    g p =
  (match create_request_
     ?absolute ?absolute_path ?https
     ~service
     ?hostname ?port ?fragment ?keep_nl_params ?nl_params ?keep_get_na_params
     g p
   with
     | Left uri ->
	 Eliom_request.http_get
         ?cookies_info:(Eliom_uri.make_cookies_info (https, service)) uri []
     | Right (uri, p) ->
       Eliom_request.http_post
         ?cookies_info:(Eliom_uri.make_cookies_info (https, service))
	 uri p)


let call_caml_service
    ?absolute ?absolute_path ?https ~service
    ?hostname ?port ?fragment ?keep_nl_params ?nl_params ?keep_get_na_params
    g p =
  call_service
    ?absolute ?absolute_path ?https
    ~service
    ?hostname ?port ?fragment ?keep_nl_params ?nl_params ?keep_get_na_params
    g p
  >>= fun s ->
  let unmarshal s : 'a =
    let (value,sent_nodes) =
      (Marshal.from_string (Url.decode s) 0:'a Eliom_types.eliom_comet_data_type)
    in
    ignore (List.map (Eliommod_cli.rebuild_xml 0L) sent_nodes);
    Eliom_unwrap.unwrap value
  in
  Lwt.return (unmarshal s)


let get_subpage
  ?absolute ?absolute_path ?https ~service ?hostname ?port ?fragment
  ?keep_nl_params ?nl_params ?keep_get_na_params
  get_params post_params =
  (*VVV Should we fail if the service does not belong to the same application? *)
  (* GRGR FIXME et s'il n'appartient pas à une application ?? *)
  lwt content = match create_request_
     ?absolute ?absolute_path ?https ~service ?hostname ?port ?fragment
     ?keep_nl_params ?nl_params ?keep_get_na_params
     get_params post_params
   with
     | Left uri ->
       Eliom_request.http_get
         ?cookies_info:(Eliom_uri.make_cookies_info (https, service)) uri []
     | Right (uri, p) ->
       Eliom_request.http_post
         ?cookies_info:(Eliom_uri.make_cookies_info (https, service)) uri p
  in
  (* GRGR FIXME *)
  assert false


(*****************************************************************************)
(* Make the back button work when only the fragment has changed ... *)
(*VVV We check the fragment every t second ... :-( *)

let write_fragment s = Dom_html.window##location##hash <- Js.string s

let read_fragment () = Js.to_string Dom_html.window##location##hash


let (fragment, set_fragment_signal) = React.S.create (read_fragment ())

let rec fragment_polling () =
  Lwt_js.sleep 0.2 >>= fun () ->
  let new_fragment = read_fragment () in
  set_fragment_signal new_fragment;
  fragment_polling ()

let _ = fragment_polling ()

let auto_change_page fragment =
  ignore
    (let l = String.length fragment in
     if (l = 0) || ((l > 1) && (fragment.[1] = '!'))
     then
       if fragment <> !current_fragment
       then
         (
         current_fragment := fragment;
         let uri =
           match l with
             | 2 -> "./" (* fix for firefox *)
             | 0 | 1 -> Eliom_request_info.full_uri
             | _ -> String.sub fragment 2 ((String.length fragment) - 2)
         in
         lwt r = Eliom_request.http_get uri [] in
	 set_content r
	 )
       else Lwt.return ()
     else Lwt.return ())

let _ = React.E.map auto_change_page (React.S.changes fragment)

(*SGO* Server generated onclicks/onsubmits

(* A closure that is registered by default to simulate <a>.
   For use with server side generated links.
 *)
let _ =
  Eliommod_cli.register_closure
    Eliom_types.a_closure_id
    (fun (cookies_info, uri) ->
      let uri = Eliommod_cli.unwrap uri in
      let cookies_info = Eliommod_cli.unwrap cookies_info in
      ignore (change_page_uri ?cookies_info uri);
      Js._false);
  Eliommod_cli.register_closure
    Eliom_client_types.get_closure_id
    (fun (cookies_info, uri) ->
      let uri = Eliommod_cli.unwrap uri in
      let node = Js.Unsafe.variable Eliom_client_types.eliom_temporary_form_node_name in
      let cookies_info = Eliommod_cli.unwrap cookies_info in
      ignore (change_page_get_form ?cookies_info node uri);
      Js._false);
  Eliommod_cli.register_closure
    Eliom_client_types.post_closure_id
    (fun (cookies_info, uri) ->
      let uri = Eliommod_cli.unwrap uri in
      let node = Js.Unsafe.variable Eliom_client_types.eliom_temporary_form_node_name in
      let cookies_info = Eliommod_cli.unwrap cookies_info in
      ignore (change_page_post_form ?cookies_info node uri);
      Js._false)

*)

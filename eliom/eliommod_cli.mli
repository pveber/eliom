(* Ocsigen
 * http://www.ocsigen.org
 * Copyright (C) 2010 Vincent Balat
 * Laboratoire PPS - CNRS Université Paris Diderot
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


(**/**)

(* Fresh name generator *)
val fresh_id : unit -> string

val get_eliom_appl_page_data_ : 
  sp:Eliom_request_info.server_params -> (int64 * int) * unit list

val wrap : sp:Eliom_request_info.server_params -> 'a -> 
  'a Eliom_client_types.data_key

val wrap_sp : sp:Eliom_request_info.server_params ->
  Eliom_client_types.server_params Eliom_client_types.data_key

val wrap_node : sp:Eliom_request_info.server_params ->
  'a XHTML5.M.elt -> 'node Eliom_client_types.data_key


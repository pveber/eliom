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


let get_default_hostname ?sp () =
  let sitedata = Eliom_request_info.find_sitedata "get_default_hostname" sp in
  sitedata.Eliom_common.config_info.Ocsigen_extensions.default_hostname

let get_default_port ?sp () =
  let sitedata = Eliom_request_info.find_sitedata "get_default_port" sp in
  sitedata.Eliom_common.config_info.Ocsigen_extensions.default_httpport

let get_default_sslport ?sp () =
  let sitedata = Eliom_request_info.find_sitedata "get_default_sslport" sp in
  sitedata.Eliom_common.config_info.Ocsigen_extensions.default_httpsport

let get_config_default_charset ~sp =
  let sp = Eliom_request_info.esp_of_sp sp in
  Ocsigen_charset_mime.default_charset
    sp.Eliom_common.sp_request.Ocsigen_extensions.request_config.Ocsigen_extensions.charset_assoc

let get_config_info ~sp =
  let sp = Eliom_request_info.esp_of_sp sp in
  sp.Eliom_common.sp_request.Ocsigen_extensions.request_config

let get_config () =
  match Eliom_common.global_register_allowed () with
  | Some _ -> !Eliommod.config
  | None -> 
    raise (Eliom_common.Eliom_function_forbidden_outside_site_loading "Eliom_config.get_config")

-- /package/intranet-reporting-openoffice/sql/intranet-reporting-openoffice-drop.sql
--
-- Copyright (c) 2003-2016 ]project-open[
--
-- All rights reserved. Please check
-- http://www.project-open.com/license/ for details.
--
-- @author frank.bergmann@project-open.com


-- Drop plugins and menus for the module
--
select  im_component_plugin__del_module('intranet-reporting-openoffice');
select  im_menu__del_module('intranet-reporting-openoffice');



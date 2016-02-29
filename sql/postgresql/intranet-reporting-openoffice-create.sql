-- /packages/intranet-reporting-openoffice/sql/postgresql/intranet-reporting-openoffice-create.sql
--
-- Copyright (c) 2003-2011 ]project-open[
--
-- All rights reserved. Please check
-- http://www.project-open.com/license/ for details.
--
-- @author frank.bergmann@project-open.com


-----------------------------------------------------------
-- Publish the standard project report
--

SELECT im_menu__new (
	null,					-- p_menu_id
	'im_menu',				-- object_type
	now(),					-- creation_date
	null,					-- creation_user
	null,					-- creation_ip
	null,					-- context_id
	'intranet-reporting-openoffice',	-- package_name
	'openoffice_project_phases_risks',	-- label
	'Project Phases & Risks (PPT)',		-- name
	'/intranet-reporting-openoffice/project-phases-risks.odp',	-- url
	100,					-- sort_order
	(select menu_id from im_menus where label = 'projects_admin'),
	null					-- p_visible_tcl
);

SELECT acs_permission__grant_permission(
	(select menu_id from im_menus where label = 'openoffice_project_phases_risks'), 
	(select group_id from groups where group_name = 'Employees'),
	'read'
);


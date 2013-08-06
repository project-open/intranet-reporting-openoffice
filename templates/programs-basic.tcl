# /packages/intranet-reporting-openoffice/www/presupuestario-avance-accumulado-clientes.tcl
#
# Copyright (c) 1998-2012 ]project-open[
# All rights reserved

# ---------------------------------------------------------------
# 1. Page Contract
# ---------------------------------------------------------------

ad_page_contract {
    @author frank.bergmann@ticket-open.com
} {
    { report_start_date "2011-01-01" }
    { report_end_date "2012-01-01" }
}

# ---------------------------------------------------------------
# Defaults & Security
# ---------------------------------------------------------------

set current_user_id [ad_maybe_redirect_for_registration]
set page_title [lang::message::lookup "" intranet-reporting-openoffice.Informe_Programas "Informe Programas"]
set context_bar [im_context_bar $page_title]

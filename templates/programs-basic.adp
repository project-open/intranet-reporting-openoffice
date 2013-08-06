<master>
<property name="title">@page_title@</property>
<property name="context_bar">@context_bar@</property>
<property name="main_navbar_label">reporting</property>

<h1>@page_title@</h1>

<table>
<tr>
<td>

	<form action="/intranet-reporting-openoffice/programs-basic.odp" method=GET>
	<table>
	<tr class=roweven>
		<td>Fecha Inicio:</td>
		<td><input type=text name=report_start_date value="@report_start_date@"></td>
	</tr>
	<tr class=roweven>
		<td>Fecha Fin:</td>
		<td><input type=text name=report_end_date value="@report_end_date@"></td>
	</tr>
<!--
	<tr class=rowodd>
		<td>Area:</td>
		<td><%= [im_cost_center_select report_area_id 0] %></td>
	</tr>
	<tr class=rowodd>
		<td>Tipo de Proyecto:</td>
		<td><%= [im_category_select -plain_p 1 tipo_de_proyecto report_project_type_id 0] %></td>
	</tr>
-->
	<tr>
		<td></td>
		<td><input type=submit value="Enviar"></td>
	</tr>
	</table>
	</form>


</td>
<td>
	

</td>
</tr>
</table>

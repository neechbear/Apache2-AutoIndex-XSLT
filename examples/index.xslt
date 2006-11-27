<?xml version="1.0" encoding="iso-8859-1"?>
<xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform" version="1.0">
	<xsl:output encoding="iso-8859-1" method="html" indent="yes" doctype-public="-//W3C//DTD HTML 4.01 Transitional//EN"/>

	<xsl:template name="nbsp">
		<xsl:text disable-output-escaping="yes">&amp;</xsl:text>
		<xsl:text>nbsp;</xsl:text>
	</xsl:template>

	<xsl:template match="/index">
<html>
	<head>
		<meta name="robots" content="noarchive,nosnippet" />
		<meta name="googlebot" content="noarchive,nosnippet" />
		<title>My Computer: [Nicola Worthington]</title>
		<style type="text/css">
			html {
			}
			p.punters {
				font-weight: bold;
				color: #ff0000;
			}
			div.Contents {
				margin: 0px 6px 6px 6px;
			}
			.center {
				margin-left: auto;
				margin-right: auto;
			}
			img {
				border: 0px;
			}
			div.SideBar {
				float: right;
			}
			div.ToolTip {
				background: #FFFFE1;
				border: 1px #000000 solid;
				padding: 7px 7px 7px 7px;
			}
			div.SideBar a, div.SideBar a:visited {
				color: #000000;
				text-decoration: none;
			}
			div.SideBar a:hover {
				text-decoration: underline;
			}
			/* a {
				color: #59080A;
			} */
			/* a:visited,a:hover {
				color: #B468A9;
			} */
			body {
				background-color: #ffffff;
			}
			th {
				text-align: left;
			}
			body, li, div, p, td, th, input {
				font-size: 8.0pt;
				font-family: Tahoma, sans-serif;
			}
			li, div {
				margin: 0cm;
				margin-bottom: 0px;
			}
			h1 {
				margin-top: 12.0pt;
				margin-right: 0cm;
				margin-bottom: 3.0pt;
				margin-left: 0cm;
				page-break-after: avoid;
				font-size: 14.0pt;
				font-family: Arial, sans-serif;
				font-weight: bold;
			}
			h2 {
				margin-top: 12.0pt;
				margin-right: 0cm;
				margin-bottom: 3.0pt;
				margin-left: 0cm;
				page-break-after: avoid;
				font-size: 12.0pt;
				font-family: Arial, sans-serif;
				font-weight: bold;
			}
			h3 {
				margin-top: 12.0pt;
				margin-right: 0cm;
				margin-bottom: 3.0pt;
				margin-left: 0cm;
				page-break-after: avoid;
				font-size: 10.0pt;
				font-family: Arial, sans-serif;
				font-weight: bold;
			}
			h4 {
				margin-top: 12.0pt;
				margin-right: 0cm;
				margin-bottom: 3.0pt;
				margin-left: 0cm;
				page-break-after: avoid;
				font-size: 10.0pt;
				font-family: Arial, sans-serif;
			}
			h5 {
				margin-top: 12.0pt;
				margin-right: 0cm;
				margin-bottom: 3.0pt;
				margin-left: 0cm;
				font-size: 11.0pt;
				font-family: Arial, sans-serif;
				font-weight: normal;
			}
			h6 {
				margin-top: 12.0pt;
				margin-right: 0cm;
				margin-bottom: 3.0pt;
				margin-left: 0cm;
				font-size: 11.0pt;
				font-family: "Times New Roman", serif;
				font-weight: normal;
				font-style: italic;
			}
 
		</style>
		<style type="text/css">
			div.dhIndex {
				font-family: Tahoma, sans-serif;
				font-size: 8pt;
				white-space: nowrap;
			}
			div.dhIndex img {
				margin-bottom: 1px;
				margin-right: 4px;
				vertical-align: middle;
				border: 0px;
				width: 16px;
				height: 16px;
			}
			div.dhIndex a {
				position: relative;
			}
			div.dhIndex a span {
				display: none;
			}
			div.dhIndex a, div.dhIndex a:visited {
				color: #000000;
				background-color: #ffffff;
				text-decoration: none;
				white-space: nowrap;
			}
			div.dhIndex a:hover {
				text-decoration: underline;
			}
		</style>

	</head>
	<body>
		<div class="Contents">
			<table cellspacing="0" cellpadding="0" border="0">	
			<tr>
				<td align="left" valign="top">
					<div class="dhIndex">
						 
						<xsl:for-each select="dir">

						<a>
							<xsl:attribute name="href"><xsl:value-of select="@id"/></xsl:attribute>
							<img src="http://www.neechi.co.uk/lib/icons/__dir.gif" width="16" height="16">
								<xsl:attribute name="alt"><xsl:value-of select="@title"/></xsl:attribute>
							</img>
						</a>  
						<!--<xsl:text disable-output-escaping="yes">&amp;nbsp;</xsl:text>-->
						<a onmouseout="window.status='';return true">
							<xsl:attribute name="href"><xsl:value-of select="@id"/></xsl:attribute>
							<xsl:attribute name="onmouseover">window.status='Type: Directory Date Modified: <xsl:value-of select="@mtime"/> Size: <xsl:value-of select="@size"/>'; return true</xsl:attribute>
							<xsl:value-of select="@title" />
							
							<span>Type: Directory<br/>Date Modified: <xsl:value-of select="@mtime"/><br/>Size: <xsl:value-of select="@size"/></span>
						</a>
						<br />
						
						</xsl:for-each>

						<!-- Now do all the files -->
						<xsl:for-each select="file">

						<a>
							<xsl:attribute name="href"><xsl:value-of select="@id"/></xsl:attribute>
							<img width="16" height="16">
								<xsl:attribute name="src">http://www.neechi.co.uk/lib/<xsl:value-of select="@icon"/></xsl:attribute>
								<xsl:attribute name="alt">[<xsl:value-of select="@ext"/>]</xsl:attribute>
							</img>
						</a>  
						<!--<xsl:text disable-output-escaping="yes">&amp;nbsp;</xsl:text>-->
						<a onmouseout="window.status='';return true">
							<xsl:attribute name="href"><xsl:value-of select="@id"/></xsl:attribute>
							<xsl:attribute name="onmouseover">window.status='Type: Directory Date Modified: <xsl:value-of select="@mtime"/> Size: <xsl:value-of select="@size"/>'; return true</xsl:attribute>
							<xsl:value-of select="@title" />
							
							<span>Type: Directory<br/>Date Modified: <xsl:value-of select="@mtime"/><br/>Size: <xsl:value-of select="@size"/></span>
						</a>
						<br />
						
						</xsl:for-each>
						
						</div>
					</td>
				</tr>
			</table>
		</div>
	</body>
</html>						
	</xsl:template>

	<!-- Leave this in for now, might need it as an example later -->	
	<!-- </xsl:text> on next line on purpose to get newline -->
	
	<!--<xsl:template name="br-replace">
		<xsl:param name="word"/>
		
		<xsl:variable name="cr">
			<xsl:text>
			</xsl:text>
		</xsl:variable>
		<xsl:choose>
			<xsl:when test="contains($word,$cr)">
				<xsl:value-of select="substring-before($word,$cr)"/>
				<br/>
				<xsl:call-template name="br-replace">
					<xsl:with-param name="word" select="substring-after($word,$cr)"/>
				</xsl:call-template>
			</xsl:when>
			<xsl:otherwise>
				<xsl:value-of select="$word"/>
			</xsl:otherwise>
		</xsl:choose>
	</xsl:template>-->
	
</xsl:stylesheet>

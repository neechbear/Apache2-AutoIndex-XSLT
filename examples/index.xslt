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
		<title><xsl:value-of select="@path" /></title>
		<style type="text/css">
			body {
				background-color: #ffffff;
				margin: 0px 0px 0px 0px;
			}

			table.dhIndex {
				font-family: Tahoma, sans-serif;
				font-size: 8pt;
				white-space: nowrap;
				height: 100%;
			}

			table.dhIndex th {
				white-space: nowrap;
			}
			table.dhIndex td {
				white-space: nowrap;
				background: #ffffff;
				padding-left: 4px;
				padding-right: 4px;
				padding-bottom: 1px;
			}
			table.dhIndex td, table.dhIndex div.inner {
				font-weight: normal;
				font-family: Tahoma, sans-serif;
				font-size: 8pt;
				text-align: left;
			}
			table.dhIndex div.outer {
				height: 15px;
				border-bottom: 1px #424142 solid;
				border-right: 1px #424142 solid;
				border-left: 1px #ffffff solid;
				border-top: 1px #ffffff solid;
			}
			table.dhIndex td.filecol {
				background: #F7F7F7;
			}
			table.dhIndex th.sizecol, table.dhIndex td.sizecol {
				text-align: right;
			}
			table.dhIndex div.inner {
				height: 13px;
				padding-left: 4px;
				padding-right: 4px;
				color: #000000;
				background: #D6D3CE;
				border-bottom: 1px #848284 solid;
				border-right: 1px #848284 solid;
				border-left: 1px #D6D3CE solid;
				border-top: 1px #D6D3CE solid; 
			}

			table.dhIndex img {
				/* margin-bottom: 1px; */
				/* margin-right: 4px; */
				margin-right: 2px;
				/* vertical-align: middle; */
				vertical-align: bottom;
				border: 0px;
				width: 16px;
				height: 16px;
			}
			table.dhIndex a {
				position: relative;
			}
			table.dhIndex a span {
				display: none;
			}
			table.dhIndex a, table.dhIndex a:visited {
				color: #000000;
				/* background-color: #ffffff; */
				text-decoration: none;
				white-space: nowrap;
			}
			table.dhIndex a:hover {
				text-decoration: underline;
			}

			table.dhIndex a:hover span {
				background: #ffffe1;
				border: 1px #000000 solid;
				padding: 7px 7px 7px 7px;
				position: absolute;
				top: 7px;
				left: 30px;
				width: 210px;
				filter:alpha(opacity=50);
				display: block;
				z-index: 1;
				-moz-opacity:0.5;
				opacity: 0.5;
			}
			table.dhIndex img.denied {
				filter:alpha(opacity=50);
				-moz-opacity:0.5;
				opacity: 0.5;
			}
		</style>
	</head>
	<body>
		<table cellspacing="0" cellpadding="0" border="0" width="100%" height="100%"
				class="dhIndex" summary="Directory listing for">
			<thead>
				<tr>
					<th scope="col" width="200" abbr="Name"><div class="outer"><div class="inner">Name</div></div></th>
					<th scope="col" width="80" abbr="Size"><div class="outer"><div class="inner" style="text-align: right;">Size</div></div></th>
					<th scope="col" width="150" abbr="Type"><div class="outer"><div class="inner">Type</div></div></th>
					<th scope="col" width="150" abbr="Date Modified"><div class="outer"><div class="inner">Date Modified</div></div></th>
					<th scope="col"><div class="outer"><div class="inner"></div></div></th>
				</tr>
			</thead>
			<tbody>
			<xsl:for-each select="updir">
				<tr>
					<td class="filecol">
						<a href="../">
							<img width="16" height="16" alt="..">
								<xsl:attribute name="src"><xsl:value-of select="@icon"/></xsl:attribute>
							</img>
						</a>
						<a href="../" onmouseover="window.status='Type: Directory'; return true" onmouseout="window.status='';return true">..<span>Type: Directory</span></a>
					</td>
					<td class="sizecol"></td>
					<td>File Folder</td>
					<td></td>
					<td></td>
				</tr>
			</xsl:for-each>

			<!-- Do the directories first as is customary -->
			<xsl:for-each select="dir">
				<tr>
					<td class="filecol">
						<a>
							<xsl:attribute name="href"><xsl:value-of select="@href"/></xsl:attribute>
							<img width="16" height="16">
								<xsl:attribute name="src"><xsl:value-of select="@icon"/></xsl:attribute>
								<xsl:attribute name="alt"><xsl:value-of select="@title"/></xsl:attribute>
							</img>
						</a>  
						<!--<xsl:text disable-output-escaping="yes">&amp;nbsp;</xsl:text>-->
						<a onmouseout="window.status='';return true">
							<xsl:attribute name="href"><xsl:value-of select="@href"/></xsl:attribute>
							<xsl:attribute name="onmouseover">window.status='Type: Directory Date Modified: <xsl:value-of select="@nicemtime"/> Size: <xsl:value-of select="@nicesize"/>'; return true</xsl:attribute>
							<xsl:value-of select="@title" />
							<span>Type: Directory<br/>Date Modified: <xsl:value-of select="@nicemtime"/><br/>Size: <xsl:value-of select="@nicesize"/></span>
						</a>
					</td>
					<td class="sizecol"></td>
					<td>File Folder</td>
					<td><xsl:value-of select="@nicemtime"/></td>
					<td></td>
				</tr>
			</xsl:for-each>

			<!-- Now do all the files -->
			<xsl:for-each select="file">
				<tr>
					<td class="filecol">
						<a>
							<xsl:attribute name="href"><xsl:value-of select="@href"/></xsl:attribute>
							<img width="16" height="16">
								<xsl:attribute name="src"><xsl:value-of select="@icon"/></xsl:attribute>
								<xsl:attribute name="alt">[<xsl:value-of select="@ext"/>]</xsl:attribute>
							</img>
						</a>  
						<!--<xsl:text disable-output-escaping="yes">&amp;nbsp;</xsl:text>-->
						<a onmouseout="window.status='';return true">
							<xsl:attribute name="href"><xsl:value-of select="@href"/></xsl:attribute>
							<xsl:attribute name="onmouseover">window.status='Type: Directory Date Modified: <xsl:value-of select="@nicemtime"/> Size: <xsl:value-of select="@nicesize"/>'; return true</xsl:attribute>
							<xsl:value-of select="@title" />
							<span>Type: Directory<br/>Date Modified: <xsl:value-of select="@nicemtime"/><br/>Size: <xsl:value-of select="@nicesize"/></span>
						</a>
					</td>
					<td class="sizecol"><xsl:value-of select="@nicesize"/></td>
					<td><xsl:value-of select="@ext"/> File</td>
					<td><xsl:value-of select="@nicemtime"/></td>
					<td></td>
				</tr>
			</xsl:for-each>

				<tr>
					<td height="100%" style="100%;" class="filecol"></td>
					<td class="sizecol"></td>
					<td></td>
					<td></td>
					<td></td>
				</tr>
			</tbody>
		</table>
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

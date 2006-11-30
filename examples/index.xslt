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
		<!-- http://search.cpan.org/~nicolaw/Apache2-AutoIndex-XSLT -->
		<meta name="robots" content="noarchive,nosnippet" />
		<meta name="googlebot" content="noarchive,nosnippet" />
		<title><xsl:value-of select="@path" /></title>
		<style type="text/css">
			body {
				background-color: #ffffff;
			}
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
			<div class="dhIndex">
				<xsl:for-each select="updir">
				<a href="../">
					<img width="16" height="16" alt="..">
						<xsl:attribute name="src"><xsl:value-of select="@icon"/></xsl:attribute>
					</img>
				</a>
				<a href="../" onmouseover="window.status='Type: Directory'; return true" onmouseout="window.status='';return true">..<span>Type: Directory</span></a>
				<br />
				</xsl:for-each>

				<xsl:for-each select="dir">

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
					<xsl:attribute name="onmouseover">window.status='Type: Directory Date Modified: <xsl:value-of select="@mtime"/> Size: <xsl:value-of select="@size"/>'; return true</xsl:attribute>
					<xsl:value-of select="@title" />

					<span>Type: Directory<br/>Date Modified: <xsl:value-of select="@mtime"/><br/>Size: <xsl:value-of select="@size"/></span>
				</a>
				<br />

				</xsl:for-each>

				<!-- Now do all the files -->
				<xsl:for-each select="file">

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
					<xsl:attribute name="onmouseover">window.status='Type: Directory Date Modified: <xsl:value-of select="@mtime"/> Size: <xsl:value-of select="@size"/>'; return true</xsl:attribute>
					<xsl:value-of select="@title" />

					<span>Type: Directory<br/>Date Modified: <xsl:value-of select="@mtime"/><br/>Size: <xsl:value-of select="@size"/></span>
				</a>
				<br />

				</xsl:for-each>
				
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

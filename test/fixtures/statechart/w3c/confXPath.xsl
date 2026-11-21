<?xml version="1.0"?> 
<!-- Copyright 1998-2003 W3C (MIT, ERCIM, Keio), All Rights Reserved. See http://www.w3.org/Consortium/Legal/. -->
<xsl:stylesheet
    xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
    xmlns:conf="http://www.w3.org/2005/scxml-conformance"
    version="2.0">
    



<!-- Copy everything that doesn't match other rules -->
<xsl:template match="/ | @* | node()">
  <xsl:copy>
    <xsl:apply-templates select="@* | node()"/>
  </xsl:copy>
</xsl:template>

<!-- Success criteria -->

<xsl:template match="//@conf:targetpass"> 
	<xsl:attribute name="target">pass</xsl:attribute>
</xsl:template>

<xsl:template match="conf:pass">
 <final xmlns="http://www.w3.org/2005/07/scxml" id="pass">
   <onentry>
     <log label="Outcome" expr="'pass'"/>
   </onentry>
 </final>
</xsl:template>

<!-- Failure criteria -->

<xsl:template match="//@conf:targetfail"> 
	<xsl:attribute name="target">fail</xsl:attribute>
</xsl:template>

<xsl:template match="conf:fail">
 <final xmlns="http://www.w3.org/2005/07/scxml" id="fail">
   <onentry>
    <log label="Outcome" expr="'fail'"/>
   </onentry>
</final>
</xsl:template>

<!-- datamodel -->
<xsl:template match="//@conf:datamodel">
	<xsl:attribute name="datamodel">xpath</xsl:attribute>
</xsl:template> 


<!-- creates id for <data> element, etc. -->
<xsl:template match="//@conf:id"> 
	<xsl:attribute name="id">Var<xsl:value-of select="." /></xsl:attribute>
</xsl:template>


<!-- creates name for <param>, etc. -->
<xsl:template match="//@conf:name"> 
	<xsl:attribute name="name">Var<xsl:value-of select="." /></xsl:attribute>
</xsl:template>


<!-- creates location for <assign>, etc. -->
<xsl:template match="//@conf:location"> 
	<xsl:attribute name="location">$Var<xsl:value-of select="." /></xsl:attribute>
</xsl:template>

<!-- names an invalid location for <assign>, etc. -->
<xsl:template match="//@conf:invalidLocation">
	<xsl:attribute name="location">foo.bar.baz </xsl:attribute>
</xsl:template>

<!-- uses system var as location for <assign>, etc. -->
<xsl:template match="//@conf:systemVarLocation"> 
	<xsl:attribute name="location">$<xsl:value-of select="." /></xsl:attribute>
</xsl:template>

<xsl:template match="//@conf:expr"> 
	<xsl:attribute name="expr"><xsl:value-of select="." /></xsl:attribute>
</xsl:template>


<!-- expr is quoted -->
<xsl:template match="//@conf:quoteExpr"> 
	<xsl:attribute name="expr">'<xsl:value-of select="." />'</xsl:attribute>
</xsl:template>

<!-- targetexpr is the corresponding ID -->
<xsl:template match="//@conf:targetVar"> 
	<xsl:attribute name="targetexpr">$Var<xsl:value-of select="." /></xsl:attribute>
</xsl:template>

<!-- an expr that yields the text child of a variable -->
<xsl:template match="//@conf:varExpr"> 
	<xsl:attribute name="expr">$Var<xsl:value-of select="." />/text()</xsl:attribute>
</xsl:template>



<!-- an expr that yields the children of a variable -->
<xsl:template match="//@conf:varChildExpr"> 
	<xsl:attribute name="expr">$Var<xsl:value-of select="." />/*</xsl:attribute>
</xsl:template>

<!-- an expr that is the value of a system variable -->
<xsl:template match="//@conf:systemVarExpr"> 
	<xsl:attribute name="expr">$<xsl:value-of select="." /></xsl:attribute>
</xsl:template>


<!-- an expr that is the value of a non-existent substructure of a variable -->
<xsl:template match="//@conf:varNonexistentStruct"> 
	<xsl:attribute name="expr">$Var<xsl:value-of select="." />.bar</xsl:attribute>
</xsl:template>


<!-- this should return a value that cannot be assigned to a var.   -->
<xsl:template match="//@conf:illegalExpr"> 
	<xsl:attribute name="expr">!1</xsl:attribute>
</xsl:template>

<!-- this should return a simple scxml script that exits as soon as it's invoked.
We assume that this script won't undergo schema validation, so we keep it concise -->
<xsl:template match="//@conf:scxmlExpr"> 
	<xsl:attribute name="expr">string('&lt;scxml&gt;&lt;final/&gt;&lt;/scxml&gt;')</xsl:attribute>
</xsl:template>


<!-- this should add 1 to the value of the specified variable -->
<xsl:template match="conf:incrementID"> 
	<assign xmlns="http://www.w3.org/2005/07/scxml">
	  <xsl:attribute name="location">$Var<xsl:value-of select="@id"/></xsl:attribute>
	  <xsl:attribute name="expr">$Var<xsl:value-of select="@id"/> + 1</xsl:attribute>
	  </assign>
	</xsl:template>
	
	<!-- this  should concatenate the value of the id2 to id1 and assign the result to id1 -->
<xsl:template match="conf:concatVars"> 
	<assign xmlns="http://www.w3.org/2005/07/scxml">
	  <xsl:attribute name="location">$Var<xsl:value-of select="@id1"/></xsl:attribute>
	  <xsl:attribute name="expr">concat($Var<xsl:value-of select="@id1"/>, $Var<xsl:value-of select="@id2"/>)</xsl:attribute>
	  </assign>
	</xsl:template>
	
<!-- assigns the sum of the values of two vars to thefirst var-->
<xsl:template match="//conf:sumVars"> 
	<assign xmlns="http://www.w3.org/2005/07/scxml">
<xsl:attribute name="location">$Var<xsl:value-of select="@id1"/></xsl:attribute>
<xsl:attribute name="expr">$Var<xsl:value-of select="@id1"/>/text() + $Var<xsl:value-of select="@id2"/>/text()</xsl:attribute>
	  </assign>
	</xsl:template>

<!-- foreach -->
<!-- this should produce literal representation of an array containing 1 2 3 in that order -->
<xsl:template match="//conf:array123"> 
<node xmlns="">1</node><node xmlns="">2</node><node xmlns="">3</node>
</xsl:template>

<!-- this uses the children of the indicated variable as the 'array' attribute -->
<xsl:template match="//@conf:arrayVar"> 
	<xsl:attribute name="array">$Var<xsl:value-of select="."/>/*</xsl:attribute>
</xsl:template>

<!-- this uses the text child of the indicated variable as the 'array' attribute -->
<xsl:template match="//@conf:arrayTextVar"> 
	<xsl:attribute name="array">$Var<xsl:value-of select="."/>/text()</xsl:attribute>
</xsl:template>

<!-- this should yield an expr that evaluates to something that is not a valid array  -->
<xsl:template match="//@conf:illegalArray">
		<xsl:attribute name="expr">(</xsl:attribute>
</xsl:template>

<xsl:template match="//@conf:item"> 
	<xsl:attribute name="item">Var<xsl:value-of select="." /></xsl:attribute>
</xsl:template>

<!-- this should return something that cannot be an variable name -->
<xsl:template match="//@conf:illegalItem"> 
	<xsl:attribute name="item">..</xsl:attribute>
</xsl:template>

<xsl:template match="//@conf:index"> 
	<xsl:attribute name="index">Var<xsl:value-of select="." /></xsl:attribute>
</xsl:template>

<!-- this should add items onto the end of the specified array, which 
is of the same type as array123 -->
<xsl:template match="conf:extendArray"> 
	<assign xmlns="http://www.w3.org/2005/07/scxml">
		<xsl:attribute name="type">lastchild</xsl:attribute>
	  <xsl:attribute name="location">$Var<xsl:value-of select="@id"/></xsl:attribute>
	  <xsl:attribute name="expr">$Var<xsl:value-of select="@id"/>/*</xsl:attribute>
	  </assign>
</xsl:template>

<xsl:template match="//conf:illegalContent"> 
	<content xmlns="http://www.w3.org/2005/07/scxml"> xyz </content>
</xsl:template>

<!-- a content element whose value is the string 'foo' -->
<xsl:template match="//conf:contentFoo"> 
	<content xmlns="http://www.w3.org/2005/07/scxml">foo</content>
</xsl:template>

<xsl:template match="//conf:someInlineVal">123</xsl:template>


<!-- this returns something that is guaranteed not to be the ID of the current session -->
<xsl:template match="//@conf:invalidSessionID"> 
	<xsl:attribute name="expr">27</xsl:attribute>
</xsl:template>

<!-- this returns something that is guaranteed not to be a valid event I/O processor -->
<xsl:template match="//@conf:invalidSendType"> 
	<xsl:attribute name="type">27</xsl:attribute>
</xsl:template>

<!-- same value in an expr -->
<xsl:template match="//@conf:invalidSendTypeExpr"> 
	<xsl:attribute name="expr">27</xsl:attribute>
</xsl:template>

<!-- templates for the expr versions of the send attributes -->

<!-- eventexpr takes the value of the specified variable -->
<xsl:template match="//@conf:eventExpr"> 
	<xsl:attribute name="eventexpr">$Var<xsl:value-of select="." /></xsl:attribute>
</xsl:template>

<!-- targetexpr takes the value of the specified variable -->
<xsl:template match="//@conf:targetExpr"> 
	<xsl:attribute name="targetexpr">$Var<xsl:value-of select="." /></xsl:attribute>
</xsl:template>

<!-- typeexpr takes the value of the specified variable -->
<xsl:template match="//@conf:typeExpr"> 
	<xsl:attribute name="typeexpr">$Var<xsl:value-of select="." /></xsl:attribute>
</xsl:template>

<!-- delayexpr takes the value of the specified variable -->
<xsl:template match="//@conf:delayFromVar"> 
	<xsl:attribute name="delayexpr">$Var<xsl:value-of select="." /></xsl:attribute>
</xsl:template>

<!-- returns a delayexpr.  this lets platforms determine how long to delay timeout
events which cause the test to fail.  The default value provided here is pretty long -->
<xsl:template match="//@conf:delay">
	<xsl:attribute name="delayexpr">'<xsl:value-of select="."/>s'</xsl:attribute>
</xsl:template>

<!--  the specified variable is used as idlocation -->
<xsl:template match="//@conf:idlocation"> 
	<xsl:attribute name="idlocation">$Var<xsl:value-of select="." /></xsl:attribute>
</xsl:template>

<!--  the specified variable is used as sendidexpr -->
<xsl:template match="//@conf:sendIDExpr"> 
	<xsl:attribute name="sendidexpr">$Var<xsl:value-of select="." /></xsl:attribute>
</xsl:template>

<!--  the specified variable is used as srcexpr -->
<xsl:template match="//@conf:srcExpr"> 
	<xsl:attribute name="srcexpr">$Var<xsl:value-of select="." /></xsl:attribute>
</xsl:template>

<!--  the specified variable is used as namelist -->
<xsl:template match="//@conf:namelist"> 
	<xsl:attribute name="namelist">$Var<xsl:value-of select="." /></xsl:attribute>
</xsl:template>

<!-- this produces a reference to an invalid namelist, i.e. on that should cause an error -->
<xsl:template match="//@conf:invalidNamelist">
	<xsl:attribute name="namelist">"foo"</xsl:attribute>
</xsl:template>

<!-- exprs that return the value of the event fields -->

<xsl:template match="//@conf:eventName"> 
	<xsl:attribute name="expr">$_event/name/text()</xsl:attribute>
</xsl:template>

<xsl:template match="//@conf:eventType"> 
	<xsl:attribute name="expr">$_event/type/text()</xsl:attribute>
</xsl:template>

<xsl:template match="//@conf:eventSendid"> 
	<xsl:attribute name="expr">$_event/sendid/text()</xsl:attribute>
</xsl:template>

<xsl:template match="//@conf:eventField"> 
	<xsl:attribute name="expr">$_event/<xsl:value-of select="."/>/text()</xsl:attribute>
</xsl:template>

<!-- returns the raw message structure as a string -->
<xsl:template match="//@conf:eventRaw"> 
	<xsl:attribute name="expr">$_event/raw/text()</xsl:attribute>
</xsl:template>

<!-- returns the value of the specified item in  _event.data  -->
<xsl:template match="//@conf:eventDataFieldValue"> 
	<xsl:attribute name="expr">$_event/data/data[@id='<xsl:value-of select="."/>']/text()</xsl:attribute>
</xsl:template>

<!-- returns the value of a KVP specified by <param> from  _event.data  -->
<xsl:template match="//@conf:eventDataParamValue"> 
	<xsl:attribute name="expr">$_event/data/data[@id='<xsl:value-of select="."/>']/text()</xsl:attribute>
</xsl:template>

<!-- returns the value of a KVP specified by Namelist from  _event.data  -->
<xsl:template match="//@conf:eventDataNamelistValue"> 
	<xsl:attribute name="expr">$_event/data/data[@id='Var<xsl:value-of select="."/>']/data/text()</xsl:attribute>
</xsl:template>

<!-- returns the location of the scxml event i/o processor -->
<xsl:template match="//@conf:scxmlEventIOLocation"> 
	<xsl:attribute name="expr">$_ioprocessors/processor[@name="http://www.w3.org/TR/scxml/#SCXMLProcessor"]/location/text()</xsl:attribute>
</xsl:template>

<!-- to test the BasicHTTP Event I/O processor -->



<!-- return an expression evaluating to the basic http access URI -->
<xsl:template match="//@conf:basicHTTPAccessURI">
 <xsl:attribute name="expr">_ioprocessors/processor[@name="http://www.w3.org/TR/scxml/#BasicHTTPEventProcessor"]/location/text()</xsl:attribute>
</xsl:template>

<!-- return a targetexpr evaluating to the basic http access URI -->
<xsl:template match="//@conf:basicHTTPAccessURITarget">
 <xsl:attribute name="targetexpr">$_ioprocessors/processor[@name="http://www.w3.org/TR/scxml/#BasicHTTPEventProcessor"]/location/text()</xsl:attribute>
</xsl:template>

<!-- generate an cond that evaluates to true if POST was used to send the message -->
<xsl:template match="//@conf:methodIsPost">
 <xsl:attribute name="cond">contains($_event/raw, 'POST')</xsl:attribute>
</xsl:template>

<!-- generate a namelist attribute containing all the ids listed in the attribute's value -->
<xsl:template match="//@conf:multipleNamelist">
 <xsl:attribute name="namelist">
 <xsl:analyze-string select="." regex="([0-9]+)">
<xsl:matching-substring>Var<xsl:value-of select="regex-group(1)"/><xsl:text>&#xa;</xsl:text></xsl:matching-substring>
</xsl:analyze-string>
</xsl:attribute>
</xsl:template>

<!-- generate a cond that evaluates to true if the event is external -->
<xsl:template match="//@conf:eventIsExternal">
 <xsl:attribute name="cond">_event.type == 'external'</xsl:attribute>
</xsl:template>



<!-- the following templates produce an expr that extracts the relevant item from _event.raw -->
<!-- returns true if _event/raw contains the var with the specified value -->
<xsl:template match="//@conf:eventIdParamHasValue">
 <xsl:attribute name="cond"><xsl:analyze-string select="." regex="([0-9]+)(\s+)(\S+)">
<xsl:matching-substring>contains($_event/raw, 'Var<xsl:value-of select="regex-group(1)"/>=<xsl:value-of select="regex-group(3)"/>')</xsl:matching-substring></xsl:analyze-string></xsl:attribute>
</xsl:template>

<!-- returns true if _event/raw contains the param with the specified value -->
<xsl:template match="//@conf:eventNamedParamHasValue">
 <xsl:attribute name="cond"><xsl:analyze-string select="." regex="([0-9]+)(\s+)(\S+)">
<xsl:matching-substring>contains($_event/raw, '<xsl:value-of select="regex-group(1)"/>=<xsl:value-of select="regex-group(3)"/>')</xsl:matching-substring></xsl:analyze-string></xsl:attribute>
</xsl:template>

<!-- Should return true if the body of _event.raw equals the specified value.  This is too weak because
it tests only that the specified string is in _event.raw, not that it is the whole body.  I don't
know if we can make this strong in XPath 1.0 -->
<xsl:template match="//@conf:messageBodyEquals">
 <xsl:attribute name="cond">contains($_event/raw, <xsl:value-of select="."/>)</xsl:attribute>
</xsl:template>


<!-- the following templates produce an expr that extracts the relevant item from _event.raw -->
<xsl:template match="//@conf:getNamedParamVal">
 <xsl:attribute name="expr">re.search('<xsl:value-of select="."/>=(\S+)$', _event.raw).groups()[0]</xsl:attribute>
</xsl:template>

<!--  if input is 1, find param Var1, etc.  -->
<xsl:template match="//@conf:getIDParamVal">
 <xsl:attribute name="expr">substring-before(substring-after('Var<xsl:value-of select="."/>=', $_event/raw), '&amp;')</xsl:attribute>
</xsl:template>

<xsl:template match="//@conf:getNthParamName">
 <xsl:attribute name="expr">re.search('\n\n(.*)', txt).group(1).split('&amp;')[<xsl:value-of select="."/>].split('=')[0]</xsl:attribute>
</xsl:template>

<xsl:template match="//@conf:getNthParamVal">
 <xsl:attribute name="expr">re.search('\n\n(.*)', txt).group(1).split('&amp;')[<xsl:value-of select="."/>].split('=')[1]</xsl:attribute>
</xsl:template>
	  
<!-- transition conditions -->
<!-- test that given var has specific value. The value expr is evaluated -->
<xsl:template match="//@conf:idVal"> 
		<xsl:attribute name="cond">
		<xsl:analyze-string select="."
			regex="([0-9]+)([=&lt;&gt;]=?)(.*)">
					<xsl:matching-substring>$Var<xsl:value-of select="regex-group(1)"/><xsl:text>/text() </xsl:text>
						<xsl:variable name="op"><xsl:value-of select="regex-group(2)"/></xsl:variable>
						<xsl:choose>
							<xsl:when test="$op='='">=</xsl:when>
							<xsl:otherwise><xsl:value-of select="$op"/></xsl:otherwise>
					 </xsl:choose>
							<xsl:value-of select="regex-group(3)"/>
					</xsl:matching-substring>

		</xsl:analyze-string>
	</xsl:attribute>
</xsl:template> 

<!-- the value is quoted -->
<xsl:template match="//@conf:idQuoteVal"> 
		<xsl:attribute name="cond">
		<xsl:analyze-string select="."
			regex="([0-9]+)([=&lt;&gt;]=?)(.*)">
<xsl:matching-substring>$Var<xsl:value-of select="regex-group(1)"/><xsl:variable name="op"><xsl:value-of select="regex-group(2)"/></xsl:variable>
<xsl:choose>
<xsl:when test="$op='=='">=</xsl:when>
<xsl:otherwise><xsl:value-of select="$op"/></xsl:otherwise></xsl:choose>'<xsl:value-of select="regex-group(3)"/>'</xsl:matching-substring>
</xsl:analyze-string>
</xsl:attribute>
</xsl:template> 

<!-- test that the specified var has the value specified by <conf:someInlineVal> -->
<xsl:template match="//@conf:idSomeVal">
	<xsl:attribute name="cond">Var<xsl:value-of select="." /> = 123</xsl:attribute>
</xsl:template>

<!-- test on the value of two vars -->
<xsl:template match="//@conf:compareIDVal"> 
		<xsl:attribute name="cond">
		<xsl:analyze-string select="."
			regex="([0-9]+)([=&lt;&gt;]=?)([0-9+])">
					<xsl:matching-substring>$Var<xsl:value-of select="regex-group(1)"/><xsl:text>/text() </xsl:text>
						<xsl:variable name="op"><xsl:value-of select="regex-group(2)"/></xsl:variable>
						<xsl:choose>
							<xsl:when test="$op='='">=</xsl:when>
							<xsl:otherwise><xsl:value-of select="$op"/></xsl:otherwise>
					 </xsl:choose>$Var<xsl:value-of select="regex-group(3)"/><xsl:text>/text() </xsl:text>
					</xsl:matching-substring>
		</xsl:analyze-string>
	</xsl:attribute>
</xsl:template> 

<!-- test that given var whose value was passed in via namelist has specific value. The value expr is evaluated -->
<xsl:template match="//@conf:namelistIdVal"> 
		<xsl:attribute name="cond">
		<xsl:analyze-string select="."
			regex="([0-9]+)([=&lt;&gt;]=?)(.*)">
					<xsl:matching-substring>$Var<xsl:value-of select="regex-group(1)"/><xsl:text>/data/text() </xsl:text>
						<xsl:variable name="op"><xsl:value-of select="regex-group(2)"/></xsl:variable>
						<xsl:choose>
							<xsl:when test="$op='='">=</xsl:when>
							<xsl:otherwise><xsl:value-of select="$op"/></xsl:otherwise>
					 </xsl:choose>
							<xsl:value-of select="regex-group(3)"/>
					</xsl:matching-substring>

		</xsl:analyze-string>
	</xsl:attribute>
</xsl:template> 

<!-- return true if variable matches value of system var (var number is first arg, system var name
is the second argument -->
<xsl:template match="//@conf:idSystemVarVal"> 
		<xsl:attribute name="cond">
		<xsl:analyze-string select="."
			regex="([0-9]+)([=&lt;&gt;]=?)(.*)">
<xsl:matching-substring>$Var<xsl:value-of select="regex-group(1)"/><xsl:variable name="op"><xsl:value-of select="regex-group(2)"/></xsl:variable>
<xsl:choose>
<xsl:when test="$op='=='">=</xsl:when>
<xsl:otherwise><xsl:value-of select="$op"/></xsl:otherwise></xsl:choose>$<xsl:value-of select="regex-group(3)"/></xsl:matching-substring>
</xsl:analyze-string>
</xsl:attribute>
</xsl:template>

<!-- test that the event's name fieldhas the value specified -->
<xsl:template match="//@conf:eventNameVal"> 
		<xsl:attribute name="cond">$_event/name = <xsl:text>'</xsl:text><xsl:value-of select="."/><xsl:text>'</xsl:text>
	</xsl:attribute>
	
</xsl:template> 
<!-- returns true if all the required fields of _event are bound -->
<xsl:template match="//@conf:eventFieldsAreBound"> 
	<xsl:attribute name="cond">$_event/name and $_event/type and $_event/sendid and $_event/origin and $_event/origintype and $_event/invokeid and $_event/data</xsl:attribute>
</xsl:template>

<!-- returns true if machine is in the state specified -->

<xsl:template match="//@conf:inState"> 
	<xsl:attribute name="cond">In('<xsl:value-of select="."/>')</xsl:attribute>
</xsl:template>

<!-- return true if specified var has been created but has no value -->
<xsl:template match="//@conf:unboundVar"> 
	<xsl:attribute name="cond">$Var<xsl:value-of select="." /> and not($Var<xsl:value-of select="." />/text()) and not($Var<xsl:value-of select="." />/*)</xsl:attribute>
</xsl:template>

<!-- return true if the specified key in event.data has the specified value -->
<xsl:template match="//@conf:eventvarVal"> 
		<xsl:attribute name="cond">
		<xsl:analyze-string select="."
			regex="([0-9]+)([=&lt;&gt;]=?)(.*)">
					<xsl:matching-substring>$_event/data/data[@id = 'Var<xsl:value-of select="regex-group(1)"/>']/text()<xsl:variable name="op"><xsl:value-of select="regex-group(2)"/></xsl:variable>
						<xsl:choose>
							<xsl:when test="$op='='">=</xsl:when>
							<xsl:otherwise><xsl:value-of select="$op"/></xsl:otherwise>
					 </xsl:choose>
							<xsl:value-of select="regex-group(3)"/>
					</xsl:matching-substring>

		</xsl:analyze-string>
	</xsl:attribute>
	
</xsl:template> 

<!-- return true if event.data field matches the specified value -->

<xsl:template match="//@conf:eventdataVal"> 
		<xsl:attribute name="cond">$_event/data = <xsl:value-of select="."/></xsl:attribute>
</xsl:template> 

<!-- test that _event.data is set to the value specified by <conf:someInlineVal> -->
<xsl:template match="//@conf:eventdataSomeVal">
	<xsl:attribute name="cond">_event/data = 123</xsl:attribute>
</xsl:template>

<xsl:template match="//@conf:emptyEventData"> 
		<xsl:attribute name="cond">not($_event/data/*)</xsl:attribute>
</xsl:template> 

<!-- return true if the _name system var has the specified quoted value -->

<xsl:template match="//@conf:nameVarVal"> 
		<xsl:attribute name="cond">$_name/text() = '<xsl:value-of select="."/>'</xsl:attribute>
</xsl:template> 

<!-- returns true if  _event.data contains the specified item -->
<xsl:template match="//@conf:eventDataHasField"> 
	<xsl:attribute name="cond">$_event/data/data[@id=<xsl:value-of select="."/>]</xsl:attribute>
</xsl:template>

<!-- return true if first var's value is a prefix of the second var's value.  Input has form "n m" where n and m are ints.-->
<xsl:template match="//@conf:varPrefix"> 
			<xsl:attribute name="cond">
		<xsl:analyze-string select="."
			regex="(\w+)(\W)(\w+)">
					<xsl:matching-substring>
contains($Var<xsl:value-of select="regex-group(3)"/>, $Var<xsl:value-of select="regex-group(1)"/><xsl:text>)</xsl:text>
					</xsl:matching-substring>
		</xsl:analyze-string>
	</xsl:attribute>
</xsl:template>  

<!-- true if id has a value -->                                                     
<xsl:template match="//@conf:isBound">                                              
	<xsl:attribute name="cond">$Var<xsl:value-of select="." />/* or $Var<xsl:value-of select="." />/text()</xsl:attribute>         
</xsl:template>  

<!-- true if id does not have an atomic value -->
<xsl:template match="//@conf:noValue"> 
	<xsl:attribute name="cond">not($Var<xsl:value-of select="." />/text() or $Var<xsl:value-of select="." />/*)</xsl:attribute>
</xsl:template>                                                                   
	
<!-- true if system var has a value -->
<xsl:template match="//@conf:systemVarIsBound"> 
	<xsl:attribute name="cond">$<xsl:value-of select="." />/text()</xsl:attribute>
</xsl:template>

<!-- returns true if specified field of _event has no value -->
<xsl:template match="//@conf:eventFieldHasNoValue"> 
	<xsl:attribute name="cond">not(string($_event/<xsl:value-of select="." />))</xsl:attribute>
</xsl:template>

<!-- returns a value that cannot be converted into a Boolean -->
<xsl:template match="//@conf:nonBoolean"> 
	<xsl:attribute name="cond">==!*</xsl:attribute>
</xsl:template>

<!-- always returns true -->
<xsl:template match="//@conf:true"> 
	<xsl:attribute name="cond">true()</xsl:attribute>
</xsl:template>

<!-- always returns false -->
<xsl:template match="//@conf:false"> 
	<xsl:attribute name="cond">0>1</xsl:attribute>
</xsl:template>



<!-- this should return an illegal target for <send> causing a send error to be raised -->
<xsl:template match="//@conf:illegalTarget"> 
	<xsl:attribute name="target">baz</xsl:attribute>
</xsl:template>

<!-- this returns an legal, but unreachable, target for <send> causing a send error to be raised -->
<xsl:template match="//@conf:unreachableTarget"> 
	<xsl:attribute name="target">#_scxml_foo</xsl:attribute>
</xsl:template>

<!-- true if the two vars/ids have the same value -->
<xsl:template match="//@conf:VarEqVar"> 
		<xsl:attribute name="cond">
		<xsl:analyze-string select="."
			regex="([0-9]+)(\W+)([0-9]+)">
					<xsl:matching-substring>$Var<xsl:value-of select="regex-group(1)"/>/text()=$Var<xsl:value-of select="regex-group(3)"/>/text()</xsl:matching-substring>
		</xsl:analyze-string>
	</xsl:attribute>
</xsl:template> 

<!-- true if the two vars/ids have the same value, which is a structure, not atomic -->
<xsl:template match="//@conf:VarEqVarStruct"> 
		<xsl:attribute name="cond">
		<xsl:analyze-string select="."
			regex="([0-9]+)(\W+)([0-9]+)">
					<xsl:matching-substring>$Var<xsl:value-of select="regex-group(1)"/>=$Var<xsl:value-of select="regex-group(3)"/></xsl:matching-substring>
		</xsl:analyze-string>
	</xsl:attribute>
</xsl:template> 

<!-- true if _event was delivered on the specified i/o processor -->
<xsl:template match="//@conf:originTypeEq"> 
	<xsl:attribute name="cond">$_event/origintype/text() = '<xsl:value-of select="."/>'</xsl:attribute>
</xsl:template>


<!-- scripting is not supported in Xpath, so not sure what to put here.  Implementers
should know not to bother to run these tests-->

<xsl:template match="conf:script">
 <script xmlns="http://www.w3.org/2005/07/scxml">
 	</script>
</xsl:template>


<xsl:template match="//@conf:scriptGoodSrc"> 
	<xsl:attribute name="src">D:\W3C\SCXMLTests\test300.py</xsl:attribute>
</xsl:template>

<xsl:template match="//@conf:scriptBadSrc"> 
	<xsl:attribute name="src">D:\foo</xsl:attribute>
</xsl:template>

<!-- sends an event back to the sender of the current event -->
<xsl:template match="conf:sendToSender">
 <send xmlns="http://www.w3.org/2005/07/scxml">
 	<xsl:attribute name="event"><xsl:value-of select="@name" /></xsl:attribute>
   <xsl:attribute name="targetexpr">$_event/origin/text()</xsl:attribute>
   <xsl:attribute name="typeexpr">$_event/origintype/text()</xsl:attribute>
   </send>
</xsl:template>

</xsl:stylesheet>
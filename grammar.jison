/* description: Parses end executes mathematical expressions. */

/* lexical grammar */
%lex

camelcaseword         [A-Z][a-zA-Z]*[0-9]*
lowercaseword         [a-z]+[0-9]*

// see http://www.w3.org/TR/html-markup/syntax.html#attribute-name
attributename         [^\s\u0000"'>/=]+

%s intag

%%
'</'{lowercaseword}'>'          return 'CLOSELOWERTAG';
'</'{camelcaseword}'>'          return 'CLOSECAMELTAG';
'<'{lowercaseword}              yytext = yytext.substr(1); this.begin('intag'); return 'BEGINLOWERTAG';
'<'{camelcaseword}              yytext = yytext.substr(1); this.begin('intag'); return 'BEGINCAMELTAG';
<intag>'/>'                     this.popState(); return 'SELFCLOSE';
<intag>'>'                      this.popState(); return 'ENDTAG';
<intag>{attributename}'='       yytext = yytext.substr(0,yyleng-1); return 'PROPERTYDECLARATION';
<intag>'"'[^"]*'"'              yytext = yytext.substr(1,yyleng-2); return 'STRING';
<intag>\s+                      /*ignore whitespaces in tags*/
'{{#'\s*[a-z]*\s*'}}'           yytext = yytext.substr(3, yyleng-5).trim(); return 'MUSTACHESECTION';
'{{^'\s*[a-z]*\s*'}}'           yytext = yytext.substr(3, yyleng-5).trim(); return 'MUSTACHEINVERTED';
'{{/'\s*[a-z]*\s*'}}'           yytext = yytext.substr(3, yyleng-5).trim(); return 'MUSTACHEEND';
'{{'\s*\.\s*'}}'                yytext = yytext.substr(2, yyleng-4).trim(); return 'MUSTACHETHIS';
'{{'\s*[a-zA-Z][a-zA-Z_]*[0-9]*\s*'}}' yytext = yytext.substr(2, yyleng-4).trim(); return 'MUSTACHESIMPLEVAR';
'{{'\s*([\w /\-.]+)\s*'}}'          yytext = yytext.substr(2, yyleng-4).trim(); return 'MUSTACHECOMPLEXVAR';
[^<>{}]+                      return 'TEXT';
<<EOF>>                       return 'EOF';
.                             return 'SINGLECHAR';
/lex

%start file

%% /* language grammar */

file
    : component EOF
        %{
          var contains = function(x){return $1.indexOf(x) > -1},
            loopfunc = "function(a){return Array.isArray(a) && a || !!a && [a] || []}",
            negatefunc = "function(a){return (a==null || a.length===0) && [a] || []}";
          return ("React.createClass({\n" +
          (contains("this.loop(") 
              ? "  loop: " + loopfunc + ",\n"
              : "") +
          (contains("this.negate(") 
              ? "  negate: " + negatefunc + ",\n"
              : "") +
          "  render: function(){\n" +
          (contains("context")
            ? "    var context = this.props;\n"
            : "") +
          "    return "+$1+";\n" +
          "  }\n" +
          "});");
        }
    ;

component
 : uniquetag
 ;

uniquetag // a tag that cannot be a list of several tags
 : tagbegin tagselfclose {$$ = $1+$2}
 | tagbegin ENDTAG tagclose {$$ = $1 + $3}
 | tagbegin ENDTAG tagsandtext tagclose {$$ = $1 + ', ' + $3 + $4}
 ;

tag : uniquetag | loop;

tagbegin
 : tagstart properties 
     {$$ = 'React.createElement(' + $1 + ', {' + $2 + '}'}
 | tagstart
     {$$ = 'React.createElement(' + $1 + ', null'}
 ;

tagstart
 : BEGINLOWERTAG {$$ = '"'+$1+'"'}
 | BEGINCAMELTAG {$$ = $1}
 ;

tagselfclose
 : SELFCLOSE
   {$$ = ')'}
 ;

tagclose
 : CLOSECAMELTAG {$$ = ')'}
 | CLOSELOWERTAG {$$ = ')'}
 ;

properties
 : PROPERTYDECLARATION string {$$ = '"' + $1 + '": ' + $2}
 | properties PROPERTYDECLARATION string {$$ = $1 + ', "' + $2 + '": ' + $3}
 ;

string
 : STRING {$$ = JSON.stringify(yytext)}
 | variable
 ;

tags
 : tag
 | tags tag {$$ = $1+','+$2}
 ;

// A mix of tags and text, like Hello<br/>I like<br/>You
tagsandtext
 : innertext
 | tagsintag
 | innertext tagsintag {$$ = $1==='""' ? $2 : $1 + ', ' + $2}
 | tagsintag innertext {$$ = $2==='""' ? $1 : $1 + ', ' + $2}
 | innertext tagsintag innertext
    {$$ = ($1==='""'? '' : $1+',') + $2 + ($3 === '""' ? '' : ','+$3)}
 ;

// A mix of tags and text that has to start and to end with a tag,
// like <br/>I like<br/>you<br/>
tagsintag
 : tag
 | tagsintag tag {$$ = $1+', '+$2}
 | tagsintag innertext tag {$$ = [$1,$2,$3].join(', ')}
 ;

loop
 : loopstart tagsandtext loopend {$$ = $1+$2+$3}
 ;

loopstart
 : MUSTACHESECTION
    {$$ = 'this.loop(context.'+yytext+').map(function(context){return '}
 | MUSTACHEINVERTED
    {$$ = 'this.negate(context.'+$1+').map(function(matched){return ';}
 ;

loopend
 : MUSTACHEEND 
   {$$ = '})'}
 ;

variable
 : MUSTACHESIMPLEVAR
   {$$ = 'context.' + yytext}
 | MUSTACHECOMPLEXVAR
   {$$ = 'context["' + yytext + '"]'}
 | MUSTACHETHIS
   {$$ = 'context'}
 ;

longtext // Text that can contain '<', '>', '{', and '}'
 : TEXT {$$ = $1}
 | SINGLECHAR {$$ = $1}
 | longtext TEXT {$$ = $1+$2}
 | longtext SINGLECHAR {$$ = $1+$2}
 ; 

//a longtext, quoted and escaped
quotedlongtext
 // Remove strings which contain only whitespaces, in order to allow indenting
 // code without affecting the result
 : longtext {$$ = ($1.trim()==='') ? '""' : JSON.stringify($longtext)}
 ;

textfragment
 : variable
 | quotedlongtext variable {$$ = $1==='""' ? $2 : $1+' + '+$2}
 | textfragment variable {$$ = $1+' + '+$2}
 | textfragment quotedlongtext variable
    {$$ = $1 + ' + ' + ($2==='""'?'':$2+'+') + $3}
 ;

innertext
 : quotedlongtext
 | textfragment
 | textfragment quotedlongtext {$$ = $2 === '""' ? $1 : $1 + ' + ' + $2}
 ;

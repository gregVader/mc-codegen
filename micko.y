%{
  #include <stdio.h>
  #include <stdlib.h>
  #include "defs.h"
  #include "symtab.h"
  #include "codegen.h"

  int yyparse(void);
  int yylex(void);
  int yyerror(char *s);
  void warning(char *s);

  extern int yylineno;
  int out_lin = 0;
  char char_buffer[CHAR_BUFFER_LENGTH];
  int error_count = 0;
  int warning_count = 0;
  int var_num = 0;
  int fun_idx = -1;
  int fcall_idx = -1;
  int lab_num = -1;
  FILE *output;
  int var_num_to_inc = 0;
  int vars_to_inc[100];
  int switch_literals[100];
  int switch_literal_num = 0;
  int switch_num = -1;
  int switch_var;
  
%}

%union {
  int i;
  char *s;
}

%token <i> _TYPE
%token _IF
%token _ELSE
%token _RETURN
%token <s> _ID
%token <s> _INT_NUMBER
%token <s> _UINT_NUMBER
%token _LPAREN
%token _RPAREN
%token _LBRACKET
%token _RBRACKET
%token _ASSIGN
%token _SEMICOLON
%token <i> _AROP
%token <i> _RELOP
%token _INC
%token _QUESTION
%token _COLON
%token _FOR
%token _SWITCH
%token _CASE
%token _BREAK
%token _DEFAULT

%type <i> num_exp exp literal
%type <i> function_call argument rel_exp if_part cond_exp

%nonassoc ONLY_IF
%nonassoc _ELSE



%%

program
  : global_vars function_list
      {  
        if(lookup_symbol("main", FUN) == NO_INDEX)
          err("undefined reference to 'main'");
      }
  ;

global_vars
  : /**/
  | global_vars global_var
  ;
  
global_var
  : _TYPE _ID _SEMICOLON
  {
  	int idx = lookup_symbol($2, GLOB);
  	if (idx==NO_INDEX)
  		insert_symbol($2, GLOB, $1, NO_ATR, NO_ATR);
  	else
  		err("redefinition of '%s'", $2);
  		
  	code("\n%s:", $2);
  	code("\n\t\tWORD\t1");
  }
  ;

function_list
  : function
  | function_list function
  ;

function
  : _TYPE _ID
      {
        fun_idx = lookup_symbol($2, FUN|GLOB);
        if(fun_idx == NO_INDEX)
          fun_idx = insert_symbol($2, FUN, $1, NO_ATR, NO_ATR);
        else 
          err("redefinition of function '%s'", $2);

        code("\n%s:", $2);
        code("\n\t\tPUSH\t%%14");
        code("\n\t\tMOV \t%%15,%%14");
      }
    _LPAREN parameter _RPAREN body
      {
        clear_symbols(fun_idx + 1);
        var_num = 0;
        
        code("\n@%s_exit:", $2);
        code("\n\t\tMOV \t%%14,%%15");
        code("\n\t\tPOP \t%%14");
        code("\n\t\tRET");
      }
  ;

parameter
  : /* empty */
      { set_atr1(fun_idx, 0); }

  | _TYPE _ID
      {
        insert_symbol($2, PAR, $1, 1, NO_ATR);
        set_atr1(fun_idx, 1);
        set_atr2(fun_idx, $1);
      }
  ;

body
  : _LBRACKET variable_list
      {
        if(var_num)
          code("\n\t\tSUBS\t%%15,$%d,%%15", 4*var_num);
        code("\n@%s_body:", get_name(fun_idx));
      }
    statement_list _RBRACKET
  ;

variable_list
  : /* empty */
  | variable_list variable
  ;

variable
  : _TYPE _ID _SEMICOLON
      {
        if(lookup_symbol($2, VAR|PAR) == NO_INDEX)
           insert_symbol($2, VAR, $1, ++var_num, NO_ATR);
        else 
           err("redefinition of '%s'", $2);
      }
  ;

statement_list
  : /* empty */
  | statement_list statement
  ;

statement
  : compound_statement
  | assignment_statement
  | if_statement
  | return_statement
  | postincrement_statement
  | for_statement
  | switch_statement
  ;
  
switch_statement
  : _SWITCH
  {
  	++switch_num;
  	code("\n@switch%d:", switch_num);
  	switch_literal_num = 0;
  	code("\n\t\tJMP\t\t@switchtest%d", switch_num);
  }
  _LPAREN _ID
  {
  	int idx = lookup_symbol($4, VAR|PAR|GLOB);
  	if(idx == NO_INDEX)
  		err("'%s' undeclared", $4);
  	switch_var = idx;
  }
  _RPAREN _LBRACKET cases
  {
  	//default labela
  	code("\n@default%d:", switch_num);
  }
  maybedefault _RBRACKET
  {
  	//JMP na kraj sa default-a
  	code("\n\t\tJMP\t\t@switchexit%d", switch_num);
  	//switchtest
  	code("\n@switchtest%d:", switch_num);
	for(int i=0; i<switch_literal_num; i++){
		gen_cmp(switch_literals[i], switch_var);
		code("\n\t\tJEQ\t\t@case%d_%s", switch_num, get_name(switch_literals[i]));
	}

  	// ako nije nijedan case skoci na default
  	code("\n\t\tJMP\t\t@default%d", switch_num);
  	
  	//kraj labela...
  	code("\n@switchexit%d:", switch_num);
  }
  ;
  
cases
  : case
  | cases case
  ;
  
case
  : _CASE literal
  {
  	if(get_type($2)!=get_type(switch_var))
  		err("incompatible types");
  		
  	for(int i=0; i<switch_literal_num; i++){
  		if(switch_literals[i] == $2)
  			err("values in case not unique");
  	}	

  	switch_literals[switch_literal_num++] = $2;
  	code("\n@case%d_%s:", switch_num, get_name($2));
  }
  _COLON statement maybebreak
  ;
  
maybebreak
  : /**/
  | _BREAK _SEMICOLON
  {
  	code("\n\t\tJMP\t\t@switchexit%d", switch_num);
  }
  ;
  
maybedefault
  : /**/
  | _DEFAULT _COLON statement
  ;

for_statement
  : _FOR _LPAREN _ID _ASSIGN literal
  {
  	int idx = lookup_symbol($3, VAR|PAR|GLOB);
  	if(idx == NO_INDEX)
  		err("'%s' undeclared", $3);
  		
  	if(get_type(idx)!=get_type($5))
  		err("incompatible types");
  		
  	$<i>$ = ++lab_num;
  	
  	gen_mov($5, idx);
  	code("\n@for%d:", lab_num);
  }
  _SEMICOLON rel_exp
  {
  	code("\n\t\t%s\t@forexit%d", opp_jumps[$8], $<i>6);
  }
  _SEMICOLON _ID _INC
  {
  	int idx = lookup_symbol($11, VAR|PAR|GLOB);
  	
  	if(idx == NO_INDEX)
  		err("'%s' undeclared", $11);
  		
  	$<i>$ = idx;
  }
  _RPAREN statement
  {
  	code("\n\t\t%s\t", ar_instructions[(get_type($<i>13) - 1)*AROP_NUMBER]);
  	gen_sym_name($<i>13);
  	code(",$1,");
  	gen_sym_name($<i>13);
  	code("\n\t\tJMP\t\t@for%d", $<i>6);
  	code("\n@forexit%d:", $<i>6);
  }
  ;

postincrement_statement
  : _ID _INC _SEMICOLON
  {
  	int idx = lookup_symbol($1, VAR|PAR|GLOB);
  	if(idx==NO_INDEX)
  		err("'%s' undeclared", $1);
  		
  	code("\n\t\t%s\t", ar_instructions[(get_type(idx)-1)*AROP_NUMBER]);
  	gen_sym_name(idx);
  	code(",$1,");
  	gen_sym_name(idx);
  	
  }
  ;

compound_statement
  : _LBRACKET statement_list _RBRACKET
  ;

assignment_statement
  : _ID _ASSIGN num_exp _SEMICOLON
      {
        int idx = lookup_symbol($1, VAR|PAR|GLOB);
        if(idx == NO_INDEX)
          err("invalid lvalue '%s' in assignment", $1);
        else
          if(get_type(idx) != get_type($3))
            err("incompatible types in assignment");
            
        for(int i = 0; i<var_num_to_inc; i++){
        	code("\n\t\t%s\t", ar_instructions[(get_type(vars_to_inc[i])-1)*AROP_NUMBER]);
        	gen_sym_name(vars_to_inc[i]);
        	code(",$1,");
        	gen_sym_name(vars_to_inc[i]);
        }
        var_num_to_inc = 0;
        gen_mov($3, idx);
      }
  ;

num_exp
  : exp

  | num_exp _AROP exp
      {
        if(get_type($1) != get_type($3))
          err("invalid operands: arithmetic operation");
        int t1 = get_type($1);    
        code("\n\t\t%s\t", ar_instructions[$2 + (t1 - 1) * AROP_NUMBER]);
        gen_sym_name($1);
        code(",");
        gen_sym_name($3);
        code(",");
        free_if_reg($3);
        free_if_reg($1);
        $$ = take_reg();
        gen_sym_name($$);
        set_type($$, t1);
      }
  ;

exp
  : literal

  | _ID
      {
        $$ = lookup_symbol($1, VAR|PAR|GLOB);
        if($$ == NO_INDEX)
          err("'%s' undeclared", $1);
      }

  | function_call
      {
        $$ = take_reg();
        gen_mov(FUN_REG, $$);
      }
  
  | _LPAREN num_exp _RPAREN
      { $$ = $2; }
  | _ID _INC
  {
  	$$ = lookup_symbol($1, VAR|PAR|GLOB);
  	if($$ == NO_INDEX)
  		err("'%s' undeclared", $1);
  		
  	vars_to_inc[var_num_to_inc++] = $$;
  	
  }
  /* conditional_operator*/
  | _LPAREN rel_exp _RPAREN _QUESTION cond_exp _COLON cond_exp
  {
  	if(get_type($5)!=get_type($7))
  		err("incompatible types");
  		
  	++lab_num;
  	code("\n\t\t%s\t@false%d", opp_jumps[$2], lab_num);
  	int reg = take_reg();
  	gen_mov($5, reg);
  	code("\n\t\tJMP\t@exit%d", lab_num);
  	code("\n@false%d:", lab_num);
  	gen_mov($7, reg);
  	code("\n@exit%d:", lab_num);
  	$$ = reg;
  	set_type($$, get_type($5));
  }
  ;

cond_exp
  : literal
  | _ID
  {
  	int idx = lookup_symbol($1, VAR|PAR|GLOB);
  	if(idx == NO_INDEX)
  		err("'%s' undeclared");
  		
  	$$ = idx;
  }
  ;

literal
  : _INT_NUMBER
      { $$ = insert_literal($1, INT); }

  | _UINT_NUMBER
      { $$ = insert_literal($1, UINT); }
  ;

function_call
  : _ID 
      {
        fcall_idx = lookup_symbol($1, FUN);
        if(fcall_idx == NO_INDEX)
          err("'%s' is not a function", $1);
      }
    _LPAREN argument _RPAREN
      {
      	for(int i = 0; i<var_num_to_inc; i++){
        	code("\n\t\t%s\t", ar_instructions[(get_type(vars_to_inc[i])-1)*AROP_NUMBER]);
        	gen_sym_name(vars_to_inc[i]);
        	code(",$1,");
        	gen_sym_name(vars_to_inc[i]);
        }
        var_num_to_inc = 0;
        
        if(get_atr1(fcall_idx) != $4)
          err("wrong number of arguments");
        code("\n\t\t\tCALL\t%s", get_name(fcall_idx));
        if($4 > 0)
          code("\n\t\t\tADDS\t%%15,$%d,%%15", $4 * 4);
        set_type(FUN_REG, get_type(fcall_idx));
        $$ = FUN_REG;
      }
  ;

argument
  : /* empty */
    { $$ = 0; }

  | num_exp
    { 
      if(get_atr2(fcall_idx) != get_type($1))
        err("incompatible type for argument");
      free_if_reg($1);
      code("\n\t\t\tPUSH\t");
      gen_sym_name($1);
      $$ = 1;
    }
  ;

if_statement
  : if_part %prec ONLY_IF
      { code("\n@exit%d:", $1); }

  | if_part _ELSE statement
      { code("\n@exit%d:", $1); }
  ;

if_part
  : _IF _LPAREN
      {
        $<i>$ = ++lab_num;
        code("\n@if%d:", lab_num);
      }
    rel_exp
      {
        code("\n\t\t%s\t@false%d", opp_jumps[$4], $<i>3);
        code("\n@true%d:", $<i>3);
      }
    _RPAREN statement
      {
        code("\n\t\tJMP \t@exit%d", $<i>3);
        code("\n@false%d:", $<i>3);
        $$ = $<i>3;
      }
  ;

rel_exp
  : num_exp
  {
  	for(int i = 0; i<var_num_to_inc; i++){
        	code("\n\t\t%s\t", ar_instructions[(get_type(vars_to_inc[i])-1)*AROP_NUMBER]);
        	gen_sym_name(vars_to_inc[i]);
        	code(",$1,");
        	gen_sym_name(vars_to_inc[i]);
        }
    var_num_to_inc = 0;
  }
  _RELOP num_exp
      {
        if(get_type($1) != get_type($4))
          err("invalid operands: relational operator");
        $$ = $3 + ((get_type($1) - 1) * RELOP_NUMBER);
        for(int i = 0; i<var_num_to_inc; i++){
        	code("\n\t\t%s\t", ar_instructions[(get_type(vars_to_inc[i])-1)*AROP_NUMBER]);
        	gen_sym_name(vars_to_inc[i]);
        	code(",$1,");
        	gen_sym_name(vars_to_inc[i]);
        }
        var_num_to_inc = 0;
        gen_cmp($1, $4);
      }
  ;

return_statement
  : _RETURN num_exp _SEMICOLON
      {
        if(get_type(fun_idx) != get_type($2))
          err("incompatible types in return");
        gen_mov($2, FUN_REG);
        code("\n\t\tJMP \t@%s_exit", get_name(fun_idx));        
      }
  ;

%%

int yyerror(char *s) {
  fprintf(stderr, "\nline %d: ERROR: %s", yylineno, s);
  error_count++;
  return 0;
}

void warning(char *s) {
  fprintf(stderr, "\nline %d: WARNING: %s", yylineno, s);
  warning_count++;
}

int main() {
  int synerr;
  init_symtab();
  output = fopen("output.asm", "w+");

  synerr = yyparse();

  clear_symtab();
  fclose(output);
  
  if(warning_count)
    printf("\n%d warning(s).\n", warning_count);

  if(error_count) {
    remove("output.asm");
    printf("\n%d error(s).\n", error_count);
  }

  if(synerr)
    return -1;  //syntax error
  else if(error_count)
    return error_count & 127; //semantic errors
  else if(warning_count)
    return (warning_count & 127) + 127; //warnings
  else
    return 0; //OK
}


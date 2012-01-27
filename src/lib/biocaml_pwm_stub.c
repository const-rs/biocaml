#include<stdio.h>

#include<caml/mlvalues.h>
#include<caml/memory.h>
#include<caml/callback.h>
#include<caml/fail.h>
#include<caml/alloc.h>
#include<caml/misc.h>

value biocaml_pwm_scan(value mat, value seq, value tol) {
  CAMLparam3(mat, seq, tol);
  int n = caml_string_length(seq);
  int i,j;

  for(i = n - 1; i >= 0; i--) {
    float score = 0.;
    for(j = 0; j < 17; j++) {
      score += i * j;
    }
  }
  CAMLreturn (Val_unit);
}

; =============================================================
; stats_scalar.asm
; Version ESCALAR (referencia) de los kernels de computo.
;
; Convencion de llamada: System V AMD64 ABI
;   enteros/punteros: rdi, rsi, rdx, rcx, r8, r9
;   flotantes:        xmm0, xmm1, xmm2, ...
;   retorno float:    xmm0
;   callee-saved:     rbx, rbp, r12-r15 (si los usa, debe preservarlos)
; =============================================================

    global sum_array
    global compute_stats
    global normalize_array

    section .text

; ---------------------------------------------------------------
; float sum_array(const float *arr, int n)
;   rdi = arr, esi = n
;   retorna la suma en xmm0
;
; IMPLEMENTADA COMO EJEMPLO: estudien este patron (recorrido,
; acumulador, condicion de salida) antes de escribir compute_stats
; y normalize_array.
; ---------------------------------------------------------------
sum_array:
    xor     eax, eax           ; eax = i = 0
    xorps   xmm0, xmm0         ; xmm0 = acumulador = 0.0

.sum_loop:
    cmp     eax, esi
    jge     .sum_done
    movss   xmm1, [rdi + rax*4]
    addss   xmm0, xmm1
    inc     eax
    jmp     .sum_loop

.sum_done:
    ret

; ---------------------------------------------------------------
; void compute_stats(const float *arr, int n,
;                     float *mean, float *var, float *min, float *max)
;   rdi = arr, esi = n, rdx = mean*, rcx = var*, r8 = min*, r9 = max*
;
;   var = varianza POBLACIONAL = sum((x - mean)^2) / n
;   Caso borde: si n == 0, escriba 0.0 en mean/var/min/max.
;
; TODO (estudiante):
;   1) Calcular mean = suma(arr) / n. Puede reutilizar sum_array con
;      'call sum_array', pero recuerde que eso destruye los
;      registros caller-saved (rax, rcx, rdx, rsi, rdi, r8-r11):
;      guarde arr/n/mean*/var*/min*/max* en registros callee-saved
;      (rbx, r12-r15) ANTES de llamar.
;   2) Recorrer el arreglo una segunda vez para acumular
;      sum((x - mean)^2) y obtener var = esa suma / n.
;   3) Recorrer el arreglo (puede combinarlo con el paso 1) llevando
;      min y max con comiss + saltos condicionales (ja/jb, etc.)
;      o con las instrucciones minss/maxss.
;   4) Guardar los resultados en las direcciones recibidas por
;      puntero: [rdx]=mean, [rcx]=var, [r8]=min, [r9]=max.
;   5) No olvide restaurar los registros callee-saved en el epilogo.


; ---------------------------------------------------------------
compute_stats:
    push    rbx
    push    rbp
    push    r12
    push    r13
    push    r14
    push    r15

    mov     rbx, rdi            ; rbx = arr
    mov     ebp, esi            ; ebp = n
    mov     r12, rdx            ; r12 = mean_ptr
    mov     r13, rcx            ; r13 = var_ptr
    mov     r14, r8             ; r14 = min_ptr
    mov     r15, r9             ; r15 = max_ptr

    test    ebp, ebp
    jle     .cs2_empty

    ; ------Reutilizando sum array creado por el profe en el instructivo para el mean
    mov     rdi, rbx
    mov     esi, ebp
    call    sum_array           ; xmm0 = suma; se llama la funcion auxiliar creada por el profe sum array
                                 ; rbx/rbp/r12-r15
    cvtsi2ss xmm4, ebp
    divss   xmm0, xmm4          ;xmm0 = mean, se genera el mean
    movss   [r12], xmm0         ; *mean
    movaps  xmm6, xmm0          ; conservar mean

	;continuacion de la funcion compute_stats.falta comprobacion por errores de sintaxis a la hora de la programacion en papel
    mov     r10, rbx
    mov     ecx, ebp
    movss   xmm1, [rbx]         ; min = arr[0] ;calculo del minimo
    movss   xmm2, [rbx]         ; max = arr[0] ;calculo del maximo

.cs2_minmax:
    movss   xmm3, [r10]
    minss   xmm1, xmm3
    maxss   xmm2, xmm3
    add     r10, 4
    dec     ecx
    jnz     .cs2_minmax

    movss   [r14], xmm1         ; *min
    movss   [r15], xmm2         ; *max

    ; --- calculo de sum((x - mean)^2)---
    mov     r10, rbx
    mov     ecx, ebp
    xorps   xmm5, xmm5

.cs2_var:
    movss   xmm3, [r10]
    subss   xmm3, xmm6
    mulss   xmm3, xmm3
    addss   xmm5, xmm3
    add     r10, 4
    dec     ecx
    jnz     .cs2_var

    cvtsi2ss xmm4, ebp
    divss   xmm5, xmm4          ; var = sum((x-mean)^2) / n
    movss   [r13], xmm5
    jmp     .cs2_ret

.cs2_empty:
    xorps   xmm0, xmm0
    movss   [r12], xmm0
    movss   [r13], xmm0
    movss   [r14], xmm0
    movss   [r15], xmm0

.cs2_ret:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbp
    pop     rbx
    ret

; ---------------------------------------------------------------





; void normalize_array(const float *in, float *out, int n,
;                       float mean, float stddev)
;   rdi = in, rsi = out, edx = n, xmm0 = mean, xmm1 = stddev
;
;   out[i] = (in[i] - mean) / stddev
;   Caso borde: si stddev == 0.0, copie in[i] en out[i] tal cual
;   (evite division por cero).
;
; TODO (estudiante): implementar el bucle escalar.
; Sugerencia: guarde mean (xmm0) y stddev (xmm1) en registros que no
; se sobrescriban dentro del bucle (por ejemplo xmm8/xmm9, que en
; System V no se usan para pasar argumentos), o vuelva a cargarlos
; en cada iteracion desde una copia guardada en la pila.
; ---------------------------------------------------------------
normalize_array:
    ; TODO: implementar
    ret

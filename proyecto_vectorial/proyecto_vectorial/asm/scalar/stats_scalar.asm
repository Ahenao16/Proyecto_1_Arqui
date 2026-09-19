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

	section.rodata ;definicion de datos de tipo lectura
	align 4 ;se alinean los datos en multiplos de 4 bytes

abs_mask: dd 0x7FFFFFFF ;--se coloca el bit de signo en cero
epsilon: dd1.0e-6 ;umbral para sttdev como cero
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


;------------inicio de la creacion de funciones------------------
; ---------------------------------------------------------------
;funcion compute stats
;objetivo de la funcion: calcular los estadisticos a partir de un arreglo de numeros de punto flotante

compute_stats: ;---inicio de la funcion---

    push    rbx ;se guardan los datos en pilas
    push    rbp
    push    r12
    push    r13
    push    r14
    push    r15

	;-----inicio de los punteros que almacenan los datos de las pilas iniciales
    mov     rbx, rdi            ; rbx = arr ;--puntero a la memoria donde inicia el arreglo
    mov     ebp, esi            ; ebp = n ;--tamano del arreglo
    mov     r12, rdx            ; r12 = mean_ptr ;--puntero que guarda el resultado de la media
    mov     r13, rcx            ; r13 = var_ptr ;--puntero que guarda el resultado de la varianza
    mov     r14, r8             ; r14 = min_ptr ;--puntero que guarda el valor minimo del arreglo
    mov     r15, r9             ; r15 = max_ptr ;--puntero que guarda el valor maximo del arreglo

    test    ebp, ebp ;--actualizacion de banderas
    jle     .cs2_empty ;--prevencion del error por cero

    ; ------Reutilizando sum array creado por el profe en el instructivo para el mean
    ;primer ciclo: mean reutilizando el sum array
    mov     rdi, rbx
    mov     esi, ebp
    call    sum_array           ; xmm0 = suma; se llama la funcion auxiliar creada por el profe sum array
                                 ; rbx/rbp/r12-r15
    cvtsi2ss xmm4, ebp
    divss   xmm0, xmm4          ;xmm0 = mean, se genera el mean
    movss   [r12], xmm0         ; *mean
    movaps  xmm6, xmm0          ; conservar mean

	;continuacion de la funcion compute_stats
	;segundo ciclo: min, max y varianza en un solo recorrido
	xor     eax, ebp            ;i=0
    movss   xmm1, [rbx]         ; min = arr[0] ;calculo del minimo
    movss   xmm2, [rbx]         ; max = arr[0] ;calculo del maximo
    xorps   xmm5, xmm5          ;acumulador

.cs3_loop:
	cmp eax, ebp
	jge .cs3_loop_done
	movss xmm3, [rbx+rax*4]    ;x=arr[i]
	minss xmm1, xmm3           ;min = min(min, x)
	maxss xmm2, xmm3           ;max = max(max, x)
	subss xmm3, xmm6           ;x- mean
	mulss xmm3, xmm3           ;(x-mean)²
	adds  xmm5, xmm3           ;acumulador
	inc   eax
	jmp   .cs3_loop

.cs3_loop_done:
    movss   [r14], xmm1         ; *min
    movss   [r15], xmm2         ; *max
    cvtsi2ss xmm4, ebp
    divss   xmm5, xmm4         ;var = sum((x-mean)²)/n
    movss   [r13], xmm5
    jmp     .cs3_ret


.cs3_empty:
    xorps   xmm0, xmm0
    movss   [r12], xmm0
    movss   [r13], xmm0
    movss   [r14], xmm0
    movss   [r15], xmm0

.cs3_ret:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbp
    pop     rbx
    ret

; ---------------------------------------------------------------
; void normalize_array(const float *in, float *out, int n,
;   float mean, float stddev)
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

;-----------funcion normalize array--------------
;objetivo de la funcion:normalizar el arreglo de punto flotantes y almacenando datos en un arreglo de salida
normalize_array:;---inicio de la funcion
	movaps xmm6, xmm0 ;xmm6 = mean (fijo todo el ciclo)
	movaps xmm7, xmm1 ;xmm7 = stddev (fijo todo el ciclo)

	test   edx, edx
	jle    .na3_done

	;---¿|stddev|< epsilon?
	movaps  xmm2, xmm7
	andps   xmm2, [abs_mask]   ;xmm2=|sttdev|
	movss   xmm3, [epsilon]
	comiss  xmm2, xmm3
	jb  .na3_copy ;|stddev| < epsilon -> se trata como 0

	xor     eax, eax

.na2_loop:
    cmp     eax, edx
    jge     .na2_done
    movss   xmm3, [rdi + rax*4]
    movss   xmm4, [rbp-4]       ; recargar mean desde la pila
    subss   xmm3, xmm4
    movss   xmm5, [rbp-8]       ; recargar stddev desde la pila
    divss   xmm3, xmm5
    movss   [rsi + rax*4], xmm3
    inc     eax
    jmp     .na2_loop

.na2_copy:
    xor     eax, eax

.na2_copy_loop:
    cmp     eax, edx
    jge     .na2_done
    movss   xmm3, [rdi + rax*4]
    movss   [rsi + rax*4], xmm3
    inc     eax
    jmp     .na2_copy_loop

.na2_done:
    mov     rsp, rbp
    pop     rbp
    ret

 section .note.GNU-stack noalloc noexec nowrite

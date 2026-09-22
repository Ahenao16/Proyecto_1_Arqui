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
	default rel
    global sum_array
    global compute_stats
    global normalize_array

	section .rodata ;definicion de datos de tipo lectura
	align 4 ;se alinean los datos en multiplos de 4 bytes

abs_mask: dd 0x7FFFFFFF ;--se coloca el bit de signo en cero
epsilon: dd 1.0e-6 ;umbral para sttdev como cero
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
;Objetivo de esta rutina - Calcular en un solo pase adicional (mas la rutina de
;sum_array), los siguientes datos estadisticos - la media, la varianza poblacional,
;el minimo y el maximo obtenidos a partir de un arreglo de datos floats y finalmente
;dejar cada resultado en la direccion de memoria que indica su puntero correspondiente

;Resumen puntual de la logica
;1 -  Guarda los parametros de entrada en registros callee-saved (rbx, rbp, r12, r13
;r14 y r15) porque se va a llamar la funcion sum_array, que puede destruir los registros
;caller-saved.

;2 - Si n <= 0 , escribe 0.0 en las 4 salidas y termina la ejecucion (caso borde)
;3 - Calcula mean(media) = sum_array(arra, n)/n(total de elementos) y lo guarda en
;(mean_ptr)

;4 - Recorre el arreglo una vez mas llevando min, max y la suma de (x - mean)elavado2
;simultaneamente

;5 - Guarda min y max en sus puntero, calcula var(varianza) = suma/n y la guarda en su
;puntero correspodiente

;6 - Restaura los registros callee-saved y retorno.

compute_stats:

	;---entradas de la funcion
	;registros que almacenan los datos de entradas
	;se almacenan en una pila
    push    rbx ;guarda rbx en la pila (la funcion lo va usar para "arr")
    push    rbp ;guarda rbp (se usa para "n" (cantidad de elementos de arreglo de in)
    push    r12 ;guarda r12 (se usa para mean_ptr (puntero de la media))
    push    r13 ;guarda r13 (se usa para var_ptr (puntero de la varianza))
    push    r14 ;guarda r14 (se usa para min_ptr (puntero del dato minimo del arreglo))
    push    r15 ;guarda r15 (se usa para max_ptr (puntero del dato maximo del arreglo))

    ; ----- copiar los argumentos recibidos por la ABI a registros que sobreviven la llamada a sum_array -----
	;-----inicio de los punteros que almacenan los datos de las pilas iniciales-------------
	;-----funcion: recibir los parametros de la funcion brindada por el profe---------------

    mov     rbx, rdi            ; rbx = arr        (puntero al primer elemento del arreglo)
    mov     ebp, esi            ; ebp = n          (cantidad de elementos, 32 bits)
    mov     r12, rdx            ; r12 = mean_ptr   (donde se debe escribir la media)
    mov     r13, rcx            ; r13 = var_ptr    (donde se debe escribir la varianza)
    mov     r14, r8             ; r14 = min_ptr    (donde se debe escribir el minimo)
    mov     r15, r9             ; r15 = max_ptr    (donde se debe escribir el maximo)

	;-----prevención de errores--------
	;se guarda el valor minimo final y el valor maximo final en las direcciones de memoria apuntadas por r14
    ; ----- caso borde: arreglo vacio o n invalido -----
    test    ebp, ebp            ; ebp AND ebp -> pone ZF=1 si n==0, SF=1 si n<0 (sin modificar ebp)
    jle     .compute_stats_arreglo_vacio   ; si n <= 0, ir directo al bloque que llena todo con 0.0

    ; ----- paso 1: media -----
	; ------Reutilizando sum array creado por el profe en el instructivo para la suma del arreglo de datos float
    ;primer ciclo: mean reutilizando el sum array
    ;calculo de la media

    mov     rdi, rbx            ; primer argumento para sum_array: arr
    mov     esi, ebp            ; segundo argumento para sum_array: n
    call    sum_array           ; xmm0 = suma total de arr[0..n-1];
    cvtsi2ss xmm4, ebp          ; convierte n (entero) a float y lo pone en xmm4
    divss   xmm0, xmm4          ; xmm0 = suma / n = media
    movss   [r12], xmm0         ; *mean_ptr = media (se escribe el resultado directo en la  memoria)
    movaps  xmm6, xmm0          ; respaldo de la media en el registro xmm6, para no perderla en el siguiente ciclo

    ; ----- paso 2: un solo recorrido para min, max y acumulado de varianza -----
    xor     eax, eax            ; i = 0 (indice del segundo recorrido)
    movss   xmm1, [rbx]         ; min = arr[0]  (valor inicial de referencia para comparar)
    movss   xmm2, [rbx]         ; max = arr[0]  (valor inicial de referencia para comparar)
    xorps   xmm5, xmm5          ; acumulador de la varianza = 0.0

.compute_stats_loop_principal:       ; incio del ciclo: procesa arr[i], actualiza min/max/acumulado
    cmp     eax, ebp            ; compara i con n
    jge     .compute_stats_loop_final   ; si i >= n, termino el recorrido -> salir del ciclo
    movss   xmm3, [rbx + rax*4] ; x = arr[i]
    minss   xmm1, xmm3          ; min = minimo(min, x)
    maxss   xmm2, xmm3          ; max = maximo(max, x)

    ; --- calculo de (x - mean)^2
	;------inicio de la sumatoria para la varianza-------
    subss   xmm3, xmm6          ; x = x - mean
    mulss   xmm3, xmm3          ; x = (x - mean)^2
    addss   xmm5, xmm3          ; acumulador_var += (x - mean)^2

    inc     eax                 ; i = i + 1
    jmp     .compute_stats_loop_principal   ; vuelve a evaluar la condicion del ciclo


.compute_stats_loop_final:      ; --- fin del recorrido: escribir resultados finales ---
    movss   [r14], xmm1         ; *min_ptr = min encontrado
    movss   [r15], xmm2         ; *max_ptr = max encontrado
    cvtsi2ss xmm4, ebp          ; vuelve a convertir n a float (xmm4 se pudo haber reusado, se recalcula)
    divss   xmm5, xmm4          ; var = acumulador_var / n  (varianza poblacional)
    movss   [r13], xmm5         ; *var_ptr = varianza
    jmp     .compute_stats_retornar   ; salta al epilogo, saltandose el bloque de "arreglo vacio"



.compute_stats_arreglo_vacio:   ; --- caso borde: n <= 0, todas las salidas se ponen en 0.0 ---
    xorps   xmm0, xmm0          ; xmm0 = 0.0
    movss   [r12], xmm0         ; *mean_ptr = 0.0
    movss   [r13], xmm0         ; *var_ptr  = 0.0
    movss   [r14], xmm0         ; *min_ptr  = 0.0
    movss   [r15], xmm0         ; *max_ptr  = 0.0

.compute_stats_retornar:        ; restaurar registros callee-saved y retornar ---
    pop     r15                 ; restaura r15 (orden inverso al push)
    pop     r14                 ; restaura r14
    pop     r13                 ; restaura r13
    pop     r12                 ; restaura r12
    pop     rbp                 ; restaura rbp
    pop     rbx                 ; restaura rbx
    ret                         ; retorna a quien llamo a compute_stats


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

	test   edx, edx ;se valida el tamano del arreglo si es menor o igual a 0 salta al final
	jle    .na2_done

	;division de flotantes para que la desviacion estandar no genere errores
	;---¿|stddev|< epsilon?
	movaps  xmm2, xmm7 ;copia desviacion estandar
	movss   xmm3, [abs_mask];carga de la mascara de bits
	andps   xmm2, xmm3   ;xmm2=|sttdev|;se elimina el bit de signo calculando el valor absoluto de la desviacion estandar
	movss   xmm3, [epsilon] ;se carga un valor epsilon
	comiss  xmm2, xmm3 ;se compara el valor de la desviacion estandar con epsilon
	jb  .na2_copy ;|stddev| < epsilon -> se trata como 0 ;si la desviacion estandar es menor a epsilon salta al siguiente ciclo

	xor     eax, eax

.na2_loop: ;inicio del codigo
    cmp     eax, edx
    jge     .na2_done
    movss   xmm3, [rdi + rax*4]   ; xmm3 = in[i]
    subss   xmm3, xmm6            ; x - mean
    divss   xmm3, xmm7            ; (x - mean) / stddev
    movss   [rsi + rax*4], xmm3   ; out[i] = resultado
    inc     eax
    jmp     .na2_loop

;ciclo de respaldo
;funcion: leer arreglo original en rdi y copiar el valor en el arreglo rsi
.na2_copy:
    xor     eax, eax

.na2_copy_loop:
    cmp     eax, edx
    jge     .na2_done
    movss   xmm3, [rdi + rax*4]
    movss   [rsi + rax*4], xmm3
    inc     eax
    jmp     .na2_copy_loop

;finalizacion del codigo
.na2_done:
    ret

 section .note.GNU-stack noalloc noexec nowrite

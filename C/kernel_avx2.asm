global arr_sum_avx2
global compute_stats_avx2
section .text

;funcion para obtener la suma del arreglo
arr_sum_avx2:
    mov eax, esi    ; EAX = n (cantidad de numeros)
    xor edx, edx    ; EDX = 0  se limpia edx
    mov ecx, 8      ; divisor = 8
    div ecx  ; para dividir se realiza la division como eax = [edx:ecx]//eax cociente edx = [edx:ecx] mod eax residuo

    mov r8d, 0 ;limpiamos los valores de registros 8 y 9 que seran usados como contadores 
    mov r9d, 0 ;R8 = contador bloques, R9 = contador sobrante

    vxorps ymm0, ymm0, ymm0 ;se colocan todos los valores del registro ymm0 de 256bits en cero (acumulador)
    vxorps xmm1, xmm1, xmm1; se inicializa el otro acumulador para el caso de reiduos en cero

    cmp eax,0
    je .remainder_sum ;si no se deben ejecutar bloques n<8 de una vez se procesa solo el sobrante

    .vector_sum:
        vmovaps ymm1, [rdi] ;se cargan 8 floats (32bytes). rdi contiene en este momento la direccion inicial del array en memoria 
        vaddps ymm0, ymm0, ymm1 ;sumo el bloque en ymm1 en el acumulador ymm0

        add r8d, 1 ;sumo 1 al contador de bloques
        add rdi, 32 ;voy al siguiente bloque del array 
        cmp r8d, eax ; si igualo la cantidad de bloques totales salto a procesar el residuo
        jne .vector_sum

    .horizontal_sum:
        vextractf128 xmm1, ymm0, 1 ;extraigo la parte alta de ymm0
        vextractf128 xmm2, ymm0, 0 ;extraigo la parte baja de ymm0

        vaddps xmm1, xmm1, xmm2 ;sumo ambas parte en xmm1=[A+E,B+F,C+G,D+H] 
        vhaddps xmm1, xmm1, xmm1 ;suma horizontal 1 xmm1=[A+E+B+F,C+G+D+H,0,0] 
        vhaddps xmm1, xmm1, xmm1 ;suma horizontal 2 xmm1=[A+E+B+F+C+G+D+H,0,0,0] 

        cmp edx,0 ;verifico si existe sobrante, de lo contrario termino
        je .ret_arr_sum

    .remainder_sum:
        vaddss xmm1, xmm1, [rdi] ;sumo el residuo a xmm1[0]
        add r9d,1 ;sumo 1 al contador de sobrantes
        add rdi,4 ;me muevo a la posicion del siguiente residuo (1 float)
        cmp r9d, edx ; si igualo la cantidad de numeros sobrantes totales termino
        jne .remainder_sum

    .ret_arr_sum:
        vmovaps xmm0, xmm1 ;pasamos el dato al registro de retorno
        vzeroupper ;pone en cero la parte alta de los registros YMM.
        ret ;retorna el dato en xmm0 por defecto



;funcion para el calculo de las distintas estadisticas
compute_stats_avx2:
; Teniendo en cuenta el orden de los argumentos de la funcion y el System V AMD64 ABI. Los datos se guardan en los registros
; RDI  = arr
; RSI  = n (o bien esi, parte baja del registro)
; XMM0 = arr_sum
; RDX  = &mean
; RCX  = &var
; R8   = &stddev
; R9   = &min
; stack = &max; 
    .mean:
        cvtsi2ss xmm1, esi ;convierto n a un float para poder operar
        vdivss xmm0, xmm0, xmm1 ;divido la suma total entre n
        vmovss [rdx], xmm0 ;
        ret



   
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
        ret ;retorna el dato en xmm0 por defecto



;funcion para el calculo de las distintas estadisticas
compute_stats_avx2:
; Teniendo en cuenta el orden de los argumentos de la funcion y el System V AMD64 ABI. Los datos se guardan en los registros
; RDI  = direccion arr 
; RSI  = n (o bien esi, parte baja del registro)
; XMM0 = arr_sum
; RDX  = &mean
; RCX  = &var
; R8   = &stddev
; R9   = &min
; stack = &max; 

    .stack_pointer_save: ;se agrega para evitar el segmentation fault existente al modificar los registros de los punteros
    sub rsp, 40 ; se reservan 40 Bytes del stack
    mov [rsp+0], rdx        ; [rsp+0]  = &mean
    mov [rsp+8], rcx        ; [rsp+8]  = &var
    mov [rsp+16], r8       ; [rsp+16] = &stddev
    mov [rsp+24], r9        ; [rsp+24] = &min 


    mov rax, [rsp+48] ;originalmente estaba el max en la dir +8 del stack se debe correr 40 posiciones
    mov [rsp+32], rax       ; [rsp+32] = &max


    mov r9, rdi ;Guardo el valor inicial de la direccion del array para poder hacer uso de este lueggo de modificarlo al calcular varianza, min, max
    .mean:
        cvtsi2ss xmm1, esi ;convierto n a un float para poder operar
        vdivss xmm0, xmm0, xmm1 ;divido la suma total entre n

        mov rax, [rsp+0]        ; Carga en RAX la dirección donde está almacenada la variable mean.
        vmovss [rax], xmm0     ; Pone xmm0 en el contenido de la direccion a la que apunta rax

    .variance:
        .set_up:
        vxorps ymm1, ymm1, ymm1 ;Acumulador para el calculo del termino cuadratico vectorialmente, tambien limpia xmm1

        mov eax, esi    
        xor edx, edx    
        mov ecx, 8      
        div ecx  ; calculamos catidad de bloques (eax) y sobrantes (edx)

        mov r10d, 0
        mov r11d, 0 ;contadores en cero
        cmp eax,0
        je .quadratic_term_remainder ;si no se deben ejecutar bloques n<8 de una vez se procesa solo el sobrante
        

        vbroadcastss ymm4, xmm0 ;llenamos todo el vector con el promedio para el calculo
        .quadratic_term_vectorial:
        vmovaps ymm2, [rdi] ;cargamos 8 numeros
        vsubps ymm3, ymm2, ymm4 ;restamos xi-u
        vmulps ymm2, ymm3, ymm3 ;elevamos al cuadrado
        vaddps ymm1, ymm1, ymm2

        add r10d, 1 ;sumo 1 al contador de bloques
        add rdi, 32 ;voy al siguiente bloque del array 
        
        cmp r10d, eax ; si no igualo la cantidad de bloques totales sigo reduciendo
        jne .quadratic_term_vectorial

        .horizontal_sum:
        vextractf128 xmm2, ymm1, 1 ;extraigo la parte alta de ymm1
        vextractf128 xmm3, ymm1, 0 ;extraigo la parte baja de ymm1
        vaddps xmm1, xmm3, xmm2
        vhaddps xmm1, xmm1, xmm1
        vhaddps xmm1, xmm1,xmm1  ; xmm1 = [(A-u)^2 + (B-u)^2 + ...,0,0,0]
        vxorps xmm2, xmm2, xmm2 ;se limpia el registro xmm2 para las operaciones con el residuo

        cmp edx,0
        je .variance_calculation ;si no hay residuo termine el calculo solo con la reduccion

        .quadratic_term_remainder:
        vmovss xmm3, [rdi]       ; XMM3 = xi
        vsubss xmm2, xmm3, xmm0 ;dato individual - media
        vmulss xmm2,xmm2,xmm2 ;elevo cuadrado
        vaddss xmm1, xmm1, xmm2

        add r11d, 1 ;sumo 1 al contador de residuo
        add rdi, 4 ;voy al siguiente numero del array 

        cmp r11d, edx
        jne .quadratic_term_remainder

        .variance_calculation:
        cvtsi2ss xmm4, esi ;convierto n a un float para poder operar en xmm4
        vdivss xmm1, xmm1, xmm4 ;divido la suma total entre n

        mov rax, [rsp+8]       ; Carga en RAX la dirección donde está almacenada la variable var.
        vmovss [rax], xmm1     ; Guarda el valor float de xmm1 en la dirección apuntada por RAX.
        
    
    .stddev:
        vsqrtss xmm1,xmm1, xmm1
        mov rax, [rsp+16]       ; Carga en RAX la dirección donde está almacenada la variable var.
        vmovss [rax], xmm1     ; Guarda el valor float de xmm1 en la dirección apuntada por RAX.

    
    .min:
    .min_setup:
        mov rdi, r9 ;restauro dir de memoria
        mov eax, esi
        xor edx, edx
        mov ecx, 8
        div ecx

        cmp eax,0
        je .min_remainder_no_blocks ;Si no hay bloques solo proceso residuo sin bloques
        vmovaps ymm1, [rdi] ;Cargo los primeros 8 nums en el registro base donde almaceno comparaciones
        mov r10d, 1 ;Ya se encuentra cargado el primer bloque (contador empieza en 1)
        xor r11d, r11d ;contador de sobrante en cero
        add rdi, 32 ;paso al siguiente bloque
        cmp r10d, eax
        je .horizontal_min ;si ya se proceso el unico bloque salto a reduccion horizontal


    .min_vectorial:
        vmovaps ymm2, [rdi] ;cargamos 8 numeros a otro reg
        vminps ymm1, ymm1, ymm2 ;comparamos los 8 numeros del acumulador con los 8 nuevos
        add r10d, 1 ;sumo 1 al contador de bloques
        add rdi, 32 ;voy al siguiente bloque del array
        cmp r10d, eax ;si no igualo la cantidad de bloques totales sigo comparando vectorialmente
        jne .min_vectorial


    .horizontal_min:
        vextractf128 xmm2, ymm1, 1 ;extraigo la parte alta
        vextractf128 xmm3, ymm1, 0 ;extraigo la parte baja
        vminps xmm1, xmm2, xmm3 ;Comparo el min de parte alta y baja
        vshufps xmm2, xmm1, xmm1, 0x4E ;Hago un shuffle para comparar los numeros con otros
        vminps xmm1, xmm1, xmm2 ;comparo los numeros
        vshufps xmm2, xmm1, xmm1, 0xB1 ;repito
        vminps xmm1, xmm1, xmm2
        ;En este punto xmm1[0] contiene el minimo de los bloques

        cmp edx,0
        je .min_return ;si no hay residuo retorno


    .min_remainder_blocks:
        .block_loop_min:
            vmovss xmm2, [rdi] ;cargo un numero individual
            vminss xmm1, xmm1, xmm2 ;comparo el numero con el minimo acumulado
            add r11d, 1 ;sumo 1 al contador de residuo
            add rdi, 4 ;me muevo a la posicion del siguiente residuo
            cmp r11d, edx ;si igualo la cantidad de sobrantes termino
            jne .block_loop_min

        jmp .min_return


    .min_remainder_no_blocks:
        xor r11d, r11d ;contador de sobrante en cero
        vmovss xmm1, [rdi] ;cargo el primer numero
        add rdi, 4 ;me muevo al siguiente numero
        add r11d, 1 ;ya se proceso el primer numero
        .no_block_loop_min:
            cmp r11d, edx
            je .min_return
            vmovss xmm2, [rdi] ;cargo el siguiente numero
            vminss xmm1, xmm1, xmm2 ;comparo los numeros
            add r11d, 1
            add rdi, 4 ;me muevo a la posicion del siguiente numero
            jmp .no_block_loop_min


    .min_return:
        mov rax, [rsp+24] ;cargo la direccion donde se almacenara el minimo
        vmovss [rax], xmm1 ;guardo el minimo en la direccion correspondiente


.max: ;exactamente la misma logica que el minimo pero con las funciones de maximo y la direccion final correcta
    .max_setup:
        mov rdi, r9 
        mov eax, esi
        xor edx, edx
        mov ecx, 8
        div ecx

        cmp eax,0
        je .max_remainder_no_blocks 
        vmovaps ymm1, [rdi] 
        mov r10d, 1 
        xor r11d, r11d 
        add rdi, 32 
        cmp r10d, eax
        je .horizontal_max 


    .max_vectorial:
        vmovaps ymm2, [rdi] 
        vmaxps ymm1, ymm1, ymm2 
        add r10d, 1 
        add rdi, 32 
        cmp r10d, eax 
        jne .max_vectorial


    .horizontal_max:
        vextractf128 xmm2, ymm1, 1 
        vextractf128 xmm3, ymm1, 0 
        vmaxps xmm1, xmm2, xmm3 
        vshufps xmm2, xmm1, xmm1, 0x4E 
        vmaxps xmm1, xmm1, xmm2 
        vshufps xmm2, xmm1, xmm1, 0xB1 
        vmaxps xmm1, xmm1, xmm2

        cmp edx,0
        je .max_return 

    .max_remainder_blocks:
        .block_loop_max:
            vmovss xmm2, [rdi] 
            vmaxss xmm1, xmm1, xmm2 
            add r11d, 1
            add rdi, 4 
            cmp r11d, edx 
            jne .block_loop_max

        jmp .max_return


    .max_remainder_no_blocks:
        xor r11d, r11d 
        vmovss xmm1, [rdi] 
        add rdi, 4 
        add r11d, 1 
        .no_block_loop_max:
            cmp r11d, edx
            je .max_return
            vmovss xmm2, [rdi] 
            vmaxss xmm1, xmm1, xmm2 
            add r11d, 1
            add rdi, 4 
            jmp .no_block_loop_max


    .max_return:
        mov rax, [rsp+32] 
        vmovss [rax], xmm1



    .rsp_original_position_return:
        add rsp, 40 ;Se devuelve rsp a la posicion original para evitar el segmentation fault
        ret
        



   
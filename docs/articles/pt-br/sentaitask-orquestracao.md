<!-- lang: pt-br | target: pt.community.intersystems.com | status: draft | published: -->
# SentaiTask: manutenção do InterSystems IRIS como flows, não como listas

<!-- after EN published: link "Read this article in English" to the English post -->

Todo administrador de IRIS tem um roteiro de manutenção na cabeça: virar o journal, checar a
integridade dos bancos grandes, olhar o espaço em disco, limpar o histórico antigo de tasks e não
começar a parte pesada se a instância já está com problema. O Task Manager agenda cada um desses
jobs separadamente. A ordem, as dependências e o "e se um falhar?" continuam na memória de alguém.

**O SentaiTask transforma esse roteiro em um flow.** Você monta os steps de manutenção num canvas,
liga uns aos outros e executa: os steps rodam em ondas paralelas, convergem em joins e podem rodar
em outros servidores IRIS. Cada step é acompanhado ao vivo, guarda seu resultado, e quem decide
cada permissão é a própria plataforma. Construímos o SentaiTask para o concurso "Build Your Own
Management Portal" da InterSystems, e ele é a única participação cujo núcleo é orquestração, e não
uma coleção de telas.

![SentaiTask executando um flow: checagens em dois servidores convergem num join](https://raw.githubusercontent.com/musketeers-br/sentai-task/master/assets/media/sentai-run.gif)

## Como um flow executa

Um flow é um grafo pequeno. A imagem acima é o flow de demonstração que vem com a demo pública:
integrity checks de dois bancos no servidor principal e de um banco num segundo servidor começam
juntos, e um join do tipo "todos precisam passar" só libera o relatório de tamanho dos bancos
quando os três terminam bem.

1. **Validar.** Antes de qualquer execução, o SentaiTask confere o flow contra a instância real:
   ciclos, tipos de step desconhecidos ou indisponíveis, parâmetros faltando, namespaces que não
   existem, categorias do Work Queue Manager que a plataforma não tem, bancos somente leitura. Cada
   problema aparece no nó a que se refere.
2. **Run now.** O canvas pede sua senha uma vez, entra na API de gerenciamento da plataforma para
   aquele run e despacha. Cada step vira um job da plataforma, com identificador próprio, na
   categoria do Work Queue Manager que você escolheu, com os limites de workers da própria IRIS.
3. **Acompanhar.** Cada nó mostra o estado (na fila, rodando, concluído, falhou, cancelado), o
   tempo, onde está rodando e o motivo da falha com as palavras exatas da plataforma. Um step que
   falhou pode ser executado de novo sozinho; um join segura o próximo step quando uma entrada
   falhou, e diz qual foi.
4. **Guardar a evidência.** Cada run escreve seu próprio log: quem disparou, cada step começando e
   terminando, um servidor que parou de responder, quem pediu o cancelamento e o resultado. A tela
   *Runs* encontra qualquer run antigo por flow e por resultado, e o *Export* salva o run num
   arquivo. <!-- after 012 merge -->

Os tipos de step formam um catálogo fechado e declarado. O operador nunca digita código: cada tipo
aponta para uma classe do repositório e para o esquema dos seus parâmetros, e o inspetor monta o
formulário a partir desse esquema
([tipos declarados](https://github.com/musketeers-br/sentai-task#declared-step-types)).

## As seis áreas

O concurso pede um portal de gerenciamento. Cobrimos cada área como algo que um flow consegue
fazer, para que as áreas trabalhem juntas em vez de ficarem em páginas separadas.

| Área | No SentaiTask |
|---|---|
| Tarefas | Flows com dependências e joins, acompanhamento ao vivo, cancelar e reexecutar cada step; o Task Manager nativo como catálogo, com filtros, suspender e retomar |
| Sistema operacional | Espaço livre por banco e por diretório de journal (Embedded Python) e o tamanho de cada banco, como steps |
| Work Queue Manager | Cada step roda numa categoria do WQM que você escolhe; as categorias podem ser lidas e editadas |
| Logs e monitoramento | Um log por run; um step *System alerts check* que só deixa o flow seguir se a plataforma não tiver alertas sérios <!-- after 013 merge --> |
| Segurança e permissões | Um step *Security posture report*: contas com %All, serviços abertos sem autenticação, auditoria desligada <!-- after 013 merge --> |
| Aplicações web e segredos | Um inventário das aplicações web (endpoints REST anônimos viram achados) e do IRIS Wallet, que lista nomes e nunca valores <!-- after 013 merge --> |

Como são steps, dá para montar um flow noturno que se recusa a começar a manutenção pesada numa
instância com alertas sérios, e que roda a mesma revisão de segurança em todos os servidores.

## Trabalho distribuído (DPI-I-588)

O portal de ideias da InterSystems tem uma ideia de gerenciador de trabalho distribuído, a
[DPI-I-588](https://ideas.intersystems.com/ideas/DPI-I-588): mandar trabalho para outras instâncias
e acompanhar tudo de um lugar só. O SentaiTask implementa essa ideia sem instalar nada do outro lado.

Você cadastra um **servidor alvo** (um endereço), e qualquer step cujo tipo roda pela API de
gerenciamento pode ser configurado para *Run on* esse alvo. No *Run now*, o canvas pede sua senha
em cada alvo; o servidor principal entra na API do alvo com o mesmo usuário e guarda só os tokens
daquele run, num global temporário apagado quando o run termina. A tela do run mostra onde cada
step rodou e com qual usuário, e um alvo que para de responder é tentado de novo sem travar o resto
do run ([como funciona](https://github.com/musketeers-br/sentai-task#-implements-dpi-i-588-distributed-work-manager)).

## Segurança por delegação

Uma ferramenta que executa manutenção privilegiada não pode virar um atalho em volta da segurança
da plataforma. Nossa regra é simples: **a plataforma decide cada permissão, no momento do uso.**

- Toda chamada à plataforma usa a credencial do próprio operador. O SentaiTask não guarda cópia do
  modelo de permissões e nunca deduz nada de um sucesso anterior.
- Quando a plataforma recusa, o operador vê as palavras da própria plataforma, sem mudança.
- Steps destrutivos pedem que você digite o banco ou namespace afetado antes do run começar.
- Antes de um cancelamento que faz a IRIS registrar um alerta, o diálogo avisa e explica.
- A demo pública roda atrás de um proxy que expõe só o canvas e as chamadas de API que ele usa; as
  contas privilegiadas usam um segredo do host, e os visitantes entram com uma conta de demo de
  privilégio mínimo, cujos limites medimos uma recusa da plataforma de cada vez
  ([o papel da demo](https://github.com/musketeers-br/sentai-task/blob/master/specs/011-demo-readiness/evidence/t001-demo-role.md)).

## Como foi construído

O SentaiTask é um backend em ObjectScript sobre a API de gerenciamento da IRIS (`/api/admin`),
com um canvas (SvelteKit e Svelte Flow) servido pela própria IRIS. Somos um time de três pessoas e
trabalhamos com especificação primeiro: cada funcionalidade tem especificação, plano, tarefas e
evidências registradas contra uma IRIS 2026.2 real, tudo no repositório
([specs](https://github.com/musketeers-br/sentai-task/tree/master/specs)).

Nossa constituição fixa seis princípios: arquitetura em camadas, conjunto fechado de capacidades,
autorização delegada, erros como valores, incrementos verificáveis e independência de tecnologia.
Os testes vêm primeiro. Hoje o backend tem mais de 300 testes unitários, o canvas mais de 180, e
mais de 80 cenários ponta a ponta rodam num navegador de verdade contra o container. Também
mantemos uma lista de limitações conhecidas, porque uma ferramenta de manutenção precisa dizer o
que ainda não faz ([limitações](https://github.com/musketeers-br/sentai-task/blob/master/docs/limitations.md)).

Escrever os testes contra uma instância real encontrou problemas reais. Um exemplo: `at` e `Join`
são palavras reservadas do SQL da IRIS, e duas consultas que usavam esses nomes sem aspas falhavam
em silêncio. Os testes pegaram os dois casos antes de qualquer usuário.

## Experimente

- **Demo pública**: o endereço está na seção *Try it* do README. Entre como `sentai-demo`, abra
  *Showcase: nightly checks across servers* e clique em *Run now*. A demo é reiniciada todo dia.
- **Na sua máquina**: clone o repositório e rode `docker compose up -d --build`. O README mostra o
  passo a passo completo ([Try it](https://github.com/musketeers-br/sentai-task#-try-it)).
- **O pacote**: [SentaiTask no Open Exchange](https://openexchange.intersystems.com/package/sentai-task).

Se um flow que valida, roda em ondas, atravessa servidores e explica o que fez é o jeito que você
quer cuidar da manutenção da IRIS, experimente, conte para nós o que falta e **vote no SentaiTask**
no concurso desta semana. Obrigado!

*Os Musketeers: José Roberto Pereira, Henry Pereira e Henrique Dias.*

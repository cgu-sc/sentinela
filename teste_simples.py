from fastapi import FastAPI
import uvicorn

app = FastAPI()

@app.get("/")
def root():
    return {"status": "TESTE OK", "mensagem": "O Python agora está falando com a rede perfeitamente!"}

if __name__ == "__main__":
    print("🚀 Iniciando teste puríssimo na porta 8001...")
    uvicorn.run(app, host="127.0.0.1", port=8001)

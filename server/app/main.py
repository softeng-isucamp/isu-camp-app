from fastapi import FastAPI

app = FastAPI(title="ISU-CAMP Backend")


@app.get("/")
def root():
    return {"message": "ISU-CAMP Backend is running"}
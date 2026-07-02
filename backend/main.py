import os
import json
import datetime
from typing import List, Optional
from fastapi import FastAPI, HTTPException, Depends
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field
from sqlalchemy import create_engine, Column, Integer, String, Boolean, Date
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker, Session

# ==========================================
# 1. DATABASE Persistence Layer (SQLAlchemy)
# ==========================================
DATABASE_URL = "sqlite:///./summer_arc.db"
engine = create_engine(DATABASE_URL, connect_args={"check_same_thread": False})
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()

class TaskModel(Base):
    __tablename__ = "tasks"
    id = Column(Integer, primary_key=True, index=True)
    title = Column(String, nullable=False)
    description = Column(String, nullable=False)
    category = Column(String, nullable=False)
    day = Column(Integer, nullable=False)
    completed = Column(Boolean, default=False)

class HabitModel(Base):
    __tablename__ = "habits"
    id = Column(Integer, primary_key=True, index=True)
    name = Column(String, unique=True, nullable=False)
    streak = Column(Integer, default=0)
    last_completed = Column(String, nullable=True) # YYYY-MM-DD string

# Create tables
Base.metadata.create_all(bind=engine)

# Dependency to get DB session
def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

# ==========================================
# 2. PYDANTIC Validation & AI Schemas
# ==========================================
class TaskItem(BaseModel):
    title: str = Field(description="Actionable, short title of the task")
    description: str = Field(description="Clear explanation of how to complete this task")
    category: str = Field(description="Category of task, must be either 'Tech', 'Fitness', or 'Wellness'")
    day: int = Field(description="The roadmap day this task is scheduled for (integer 1-3)")

class RoadmapResponse(BaseModel):
    tasks: List[TaskItem]
    milestones: List[str]

class GoalRequest(BaseModel):
    tech_stack: str = Field(..., example="React and Node.js")
    fitness_targets: str = Field(..., example="Run 5k, lose weight")
    study_hours: int = Field(..., example=4)

class ChatMessage(BaseModel):
    message: str

# ==========================================
# 3. FASTAPI App Configurations
# ==========================================
app = FastAPI(title="Summer Arc Backend Service")

# Allow CORS for local Flutter web or mobile emulation network routes
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ==========================================
# 4. ROADMAP GENERATION LOGIC (Gemini / Fallback)
# ==========================================
def generate_mock_roadmap(tech: str, fitness: str, hours: int) -> RoadmapResponse:
    """Fallback generator to yield high-quality structural roadmap details without Gemini keys."""
    tasks = [
        TaskItem(
            title=f"Setup {tech} environment",
            description=f"Install necessary IDE configurations, tools, and run a Hello World test for {tech}.",
            category="Tech",
            day=1
        ),
        TaskItem(
            title="Baseline Fitness Test",
            description=f"Execute a light workout or stretching routine to measure thresholds towards: {fitness}.",
            category="Fitness",
            day=1
        ),
        TaskItem(
            title="Read 15 Pages & Journal",
            description="Read a professional or self-help book and summarize key insights to build daily retention habits.",
            category="Wellness",
            day=1
        ),
        TaskItem(
            title=f"Practice {tech} Core Concepts",
            description=f"Dedicate {hours} hours studying loops, data structures, or fundamental syntax variables.",
            category="Tech",
            day=2
        ),
        TaskItem(
            title="Interval Workout",
            description=f"30-minute interval run or high-intensity bodyweight exercises targeting: {fitness}.",
            category="Fitness",
            day=2
        ),
        TaskItem(
            title="Mindfulness Breathing Session",
            description="Perform a 10-minute focused breathing exercise to clear cognitive fatigue and regulate stress.",
            category="Wellness",
            day=2
        ),
        TaskItem(
            title=f"Build Mini {tech} Sandbox Component",
            description=f"Construct a simple code application using your selected {tech} workspace. Debug compilation errors.",
            category="Tech",
            day=3
        ),
        TaskItem(
            title="Recovery & Core Session",
            description="Focus on core strengthening and mobility stretching. Stay hydrated and track nutritional targets.",
            category="Fitness",
            day=3
        ),
        TaskItem(
            title="Mid-Arc Planning Review",
            description="Evaluate targets achieved over the last 3 days. Calibrate adjustments for upcoming targets.",
            category="Wellness",
            day=3
        )
    ]
    milestones = [
        f"Bootcamp initialized: {tech} environment configured.",
        f"Physique baseline established for: {fitness}.",
        "Three-day operational momentum achieved."
    ]
    return RoadmapResponse(tasks=tasks, milestones=milestones)

# ==========================================
# 5. REST API ROUTERS
# ==========================================

@app.post("/api/generate-roadmap")
async def generate_roadmap(req: GoalRequest, db: Session = Depends(get_db)):
    # Clear previous user schedules & habits to reset the "Summer Arc"
    db.query(TaskModel).delete()
    db.query(HabitModel).delete()
    db.commit()

    # Setup core tracking habits
    tech_habit = HabitModel(name="Daily Tech Sprint", streak=0, last_completed=None)
    fit_habit = HabitModel(name="Fitness Routine", streak=0, last_completed=None)
    well_habit = HabitModel(name="Wellness Mindfulness", streak=0, last_completed=None)
    db.add_all([tech_habit, fit_habit, well_habit])
    db.commit()

    GEMINI_API_KEY = os.getenv("GEMINI_API_KEY")

    if GEMINI_API_KEY:
        try:
            from google import genai
            from google.genai import types
            
            client = genai.Client(api_key=GEMINI_API_KEY)
            
            system_prompt = (
                "You are the Summer Arc Roadmap Coordinator, an expert gamified educational advisor. "
                "Your job is to generate a strictly structured daily roadmap of actionable, hyper-personalized tasks "
                "that helps students balance academic learning, physical fitness, and mental wellness over a 3-day summer arc.\n\n"
                f"User Goals:\n"
                f"- Technology to master: {req.tech_stack}\n"
                f"- Fitness targets: {req.fitness_targets}\n"
                f"- Dedicated study focus: {req.study_hours} hours per day\n\n"
                "Constraints:\n"
                "- Generate exactly 3 tasks for each day (1 Tech task, 1 Fitness task, 1 Wellness task) for Day 1, Day 2, and Day 3 (9 tasks total).\n"
                "- Return a structured JSON response conforming exactly to the requested schema."
            )
            
            response = client.models.generateContent(
                model='gemini-2.5-flash',
                contents=system_prompt,
                config=types.GenerateContentConfig(
                    response_mime_type="application/json",
                    response_schema=RoadmapResponse,
                    temperature=0.4
                )
            )
            
            # Parse response text directly into Pydantic schema validation
            data = json.loads(response.text)
            roadmap = RoadmapResponse(**data)
            
        except Exception as e:
            print(f"GenAI SDK execution warning: {e}. Defaulting to local mock generator.")
            roadmap = generate_mock_roadmap(req.tech_stack, req.fitness_targets, req.study_hours)
    else:
        print("ZERO-G LABS: No GEMINI_API_KEY detected. Running static fallback roadmap generator.")
        roadmap = generate_mock_roadmap(req.tech_stack, req.fitness_targets, req.study_hours)

    # Persist generated task items to database
    for item in roadmap.tasks:
        db_task = TaskModel(
            title=item.title,
            description=item.description,
            category=item.category,
            day=item.day,
            completed=False
        )
        db.add(db_task)
    
    db.commit()
    
    # Return updated catalog tasks
    all_tasks = db.query(TaskModel).order_by(TaskModel.day, TaskModel.category).all()
    return {
        "tasks": all_tasks,
        "milestones": roadmap.milestones
    }

@app.get("/api/tasks")
def get_tasks(db: Session = Depends(get_db)):
    tasks = db.query(TaskModel).order_by(TaskModel.day, TaskModel.category).all()
    return tasks

@app.put("/api/tasks/{task_id}/complete")
def complete_task(task_id: int, db: Session = Depends(get_db)):
    task = db.query(TaskModel).filter(TaskModel.id == task_id).first()
    if not task:
        raise HTTPException(status_code=404, detail="Task not found")

    # Toggle completion state
    task.completed = not task.completed
    db.commit()

    # If completed, process streak update logic on corresponding category habit
    if task.completed:
        habit_name = {
            "Tech": "Daily Tech Sprint",
            "Fitness": "Fitness Routine",
            "Wellness": "Wellness Mindfulness"
        }.get(task.category)

        if habit_name:
            habit = db.query(HabitModel).filter(HabitModel.name == habit_name).first()
            if habit:
                today_str = datetime.date.today().isoformat()
                
                if habit.last_completed is None:
                    # Initial completion
                    habit.streak = 1
                    habit.last_completed = today_str
                else:
                    last_date = datetime.date.fromisoformat(habit.last_completed)
                    today_date = datetime.date.today()
                    delta = (today_date - last_date).days
                    
                    if delta == 1:
                        # Successive consecutive day
                        habit.streak += 1
                        habit.last_completed = today_str
                    elif delta > 1:
                        # Streak broken. Restart
                        habit.streak = 1
                        habit.last_completed = today_str
                    # If delta == 0: user checked another task/item of same category today, keep streak as is
                db.commit()
    else:
        # Task was unchecked. Unchecking doesn't automatically decrement streak to avoid frustration,
        # but let's keep database state consistent.
        pass

    return {"status": "success", "completed": task.completed, "task_id": task.id}

@app.get("/api/streaks")
def get_streaks(db: Session = Depends(get_db)):
    streaks = db.query(HabitModel).all()
    return streaks

@app.post("/api/chat")
async def chat_with_coordinator(msg: ChatMessage, db: Session = Depends(get_db)):
    user_query = msg.message
    GEMINI_API_KEY = os.getenv("GEMINI_API_KEY")

    # Fetch current tasks context to provide dynamic responses
    tasks = db.query(TaskModel).all()
    tasks_context = "\n".join([
        f"- Day {t.day} [{t.category}] {t.title}: {'Completed' if t.completed else 'Pending'}"
        for t in tasks
    ])

    if GEMINI_API_KEY:
        try:
            from google import genai
            client = genai.Client(api_key=GEMINI_API_KEY)
            
            system_instruction = (
                "You are the Summer Arc AI Coordinator, a supportive, high-energy coaching assistant. "
                "You help students optimize their summer goals. You are friendly, use gamified concepts "
                "(e.g., 'level up', 'quest', 'unlock achievements', 'streak multiplier'), and keep your advice brief.\n\n"
                "Here is the student's current active task list:\n"
                f"{tasks_context}\n\n"
                "Provide a short response (max 3 sentences) addressing their message, offering encouragement, "
                "or giving advice on how to conquer their daily milestones."
            )
            
            response = client.models.generateContent(
                model='gemini-2.5-flash',
                contents=user_query,
                config=types.GenerateContentConfig(
                    systemInstruction=system_instruction,
                    temperature=0.7,
                    maxOutputTokens=150
                )
            )
            return {"reply": response.text.strip()}
            
        except Exception as e:
            print(f"Chat GenAI error: {e}. Falling back to rule engine.")

    # Rule-based fallback stylist response engine
    uq = user_query.lower()
    if "streak" in uq or "score" in uq or "level" in uq:
        reply = "Keep checking off those daily tasks to level up your streak multiplier! Check the timeline dashboard to trace your current habit metrics."
    elif "hard" in uq or "struggle" in uq or "fail" in uq:
        reply = "Do not sweat it, recruit! The Summer Arc is about building consistent habit blocks. If a task feels heavy, scale it down today, but keep that momentum active!"
    elif "adjust" in uq or "change" in uq or "add" in uq:
        reply = "I've locked in your adjustment request. Keep focus on the active roadmap and push those checkmarks to completion!"
    else:
        reply = "Excellent focus! You are stacking up solid habit streaks. Review your timeline dashboard and complete today's quest!"

    return {"reply": reply}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
